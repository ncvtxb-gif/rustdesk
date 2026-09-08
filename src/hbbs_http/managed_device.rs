use hbb_common::{
    anyhow::{anyhow, bail, Context},
    base64::{self, Variant},
    config::{keys, Config, OVERWRITE_SETTINGS},
    sha2::{Digest, Sha256},
    tls::TlsType,
    ResultType,
};
use serde::{Deserialize, Serialize};
use std::sync::atomic::{AtomicUsize, Ordering};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

const MANAGED_HTTP_TIMEOUT: Duration = Duration::from_secs(12);
const MANAGED_BODY_TIMEOUT: Duration = Duration::from_secs(5);
const MANAGED_LOCK_TIMEOUT: Duration = Duration::from_secs(5);
pub(crate) const MANAGED_IDENTITY_IPC_TIMEOUT_MS: u64 = 35_000;

static BOOTSTRAPS_IN_PROGRESS: AtomicUsize = AtomicUsize::new(0);
lazy_static::lazy_static! {
    static ref BOOTSTRAP_LOCK: hbb_common::tokio::sync::Mutex<()> = Default::default();
}

struct BootstrapGuard;

impl BootstrapGuard {
    fn begin() -> Self {
        BOOTSTRAPS_IN_PROGRESS.fetch_add(1, Ordering::SeqCst);
        Self
    }
}

impl Drop for BootstrapGuard {
    fn drop(&mut self) {
        BOOTSTRAPS_IN_PROGRESS.fetch_sub(1, Ordering::SeqCst);
    }
}

pub fn bootstrap_in_progress() -> bool {
    BOOTSTRAPS_IN_PROGRESS.load(Ordering::SeqCst) != 0
}

#[derive(Serialize)]
struct ManagedDeviceBootstrapRequest<'a> {
    machine_uuid: &'a str,
    platform: &'static str,
}

#[derive(Serialize)]
struct ManagedDeviceAuthHashRequest<'a> {
    hash: &'a str,
}

#[derive(Debug, Deserialize)]
pub struct ManagedDeviceBootstrapResponse {
    pub rustdesk_id: String,
    pub permanent_password: String,
    pub password_version: u64,
    pub status: String,
    pub machine_uuid: String,
    pub session_expires_at: u64,
}

fn validate_locked_api_url(api_url: Option<&str>) -> ResultType<url::Url> {
    let api_url = api_url
        .filter(|value| !value.trim().is_empty())
        .context("enterprise API server is not locked")?;
    let parsed = url::Url::parse(api_url).context("invalid enterprise API server URL")?;
    if parsed.scheme() != "https"
        || parsed.host_str().is_none()
        || !parsed.username().is_empty()
        || parsed.password().is_some()
    {
        bail!("enterprise API server must be a credential-free HTTPS URL");
    }
    Ok(parsed)
}

fn validate_bootstrap_status(status: u16) -> ResultType<()> {
    if status == 200 {
        Ok(())
    } else {
        bail!("managed device bootstrap was rejected with HTTP {status}")
    }
}

fn validate_auth_hash_status(status: u16) -> ResultType<()> {
    if status == 200 || status == 204 {
        Ok(())
    } else {
        bail!("managed device auth hash upload was rejected with HTTP {status}")
    }
}

fn compatible_password_hash(password: &str, salt: &str) -> String {
    let mut hasher = Sha256::new();
    hasher.update(password.as_bytes());
    hasher.update(salt.as_bytes());
    let digest = hasher.finalize();
    base64::encode(&digest, Variant::Original)
}

fn validate_bootstrap_response(
    response: &ManagedDeviceBootstrapResponse,
    expected_machine_uuid: &str,
) -> ResultType<()> {
    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs();
    validate_bootstrap_response_at(response, expected_machine_uuid, now)
}

fn validate_bootstrap_response_at(
    response: &ManagedDeviceBootstrapResponse,
    expected_machine_uuid: &str,
    now: u64,
) -> ResultType<()> {
    if response.machine_uuid != expected_machine_uuid {
        bail!("managed device bootstrap machine UUID mismatch");
    }
    if response.status != "active" {
        bail!("managed device identity is not active");
    }
    if response.password_version == 0 {
        bail!("managed device credential version is invalid");
    }
    if response.session_expires_at == 0 || response.session_expires_at <= now {
        bail!("managed device login session is expired");
    }
    if response.rustdesk_id.is_empty() || response.permanent_password.is_empty() {
        bail!("managed device bootstrap response is incomplete");
    }
    Ok(())
}

pub async fn bootstrap(access_token: &str) -> ResultType<()> {
    let _bootstrap_guard = BootstrapGuard::begin();
    let _bootstrap_lock = hbb_common::tokio::time::timeout(
        MANAGED_LOCK_TIMEOUT,
        BOOTSTRAP_LOCK.lock(),
    )
    .await
    .context("managed device bootstrap is busy")?;
    if access_token.trim().is_empty() {
        bail!("missing API access token");
    }
    let locked_api = OVERWRITE_SETTINGS
        .read()
        .unwrap()
        .get(keys::OPTION_API_SERVER)
        .cloned();
    let api_url = validate_locked_api_url(locked_api.as_deref())?;
    let machine_uuid = crate::encode64(hbb_common::get_uuid());
    let endpoint = api_url
        .join("/api/managed-device/bootstrap")
        .context("invalid managed device bootstrap endpoint")?;
    // Bootstrap carries a bearer token and managed credential. Never use the
    // generic client's invalid-certificate fallback for this exchange.
    let client = super::create_http_client_async(TlsType::Rustls, false);
    let response = hbb_common::tokio::time::timeout(
        MANAGED_HTTP_TIMEOUT,
        client
            .post(endpoint)
            .bearer_auth(access_token)
            .json(&ManagedDeviceBootstrapRequest {
                machine_uuid: &machine_uuid,
                platform: "windows",
            })
            .send(),
    )
        .await
        .context("managed device bootstrap request timed out")?
        .context("managed device bootstrap request failed")?;
    validate_bootstrap_status(response.status().as_u16())?;
    let identity = hbb_common::tokio::time::timeout(
        MANAGED_BODY_TIMEOUT,
        response.json::<ManagedDeviceBootstrapResponse>(),
    )
        .await
        .context("managed device bootstrap response timed out")?
        .context("invalid managed device bootstrap response")?;
    validate_bootstrap_response(&identity, &machine_uuid)?;
    Config::apply_managed_identity(
        &identity.rustdesk_id,
        &identity.permanent_password,
        identity.session_expires_at,
    )?;

    let auth_hash = compatible_password_hash(&identity.permanent_password, &Config::get_salt());
    let upload_result = async {
        let auth_hash_endpoint = api_url
            .join("/api/managed-device/auth-hash")
            .context("invalid managed device auth hash endpoint")?;
        let response = hbb_common::tokio::time::timeout(
            MANAGED_HTTP_TIMEOUT,
            client
                .put(auth_hash_endpoint)
                .bearer_auth(access_token)
                .json(&ManagedDeviceAuthHashRequest { hash: &auth_hash })
                .send(),
        )
            .await
            .context("managed device auth hash upload timed out")?
            .context("managed device auth hash upload failed")?;
        validate_auth_hash_status(response.status().as_u16())
    }
    .await;

    if let Err(upload_error) = upload_result {
        return match Config::clear_managed_identity() {
            Ok(()) => Err(upload_error),
            Err(clear_error) => Err(anyhow!(
                "managed device auth hash upload failed and identity rollback failed: {upload_error}; {clear_error}"
            )),
        };
    }
    Ok(())
}

pub async fn clear() -> ResultType<()> {
    let _bootstrap_lock = BOOTSTRAP_LOCK.lock().await;
    Config::clear_managed_identity()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn valid_response() -> ManagedDeviceBootstrapResponse {
        ManagedDeviceBootstrapResponse {
            rustdesk_id: "123456789".to_owned(),
            permanent_password: "managed-secret".to_owned(),
            password_version: 1,
            status: "active".to_owned(),
            machine_uuid: "machine-uuid".to_owned(),
            session_expires_at: u64::MAX,
        }
    }

    #[test]
    fn rejects_unlocked_or_non_https_api_urls() {
        assert!(validate_locked_api_url(None).is_err());
        assert!(validate_locked_api_url(Some("http://api.example.test")).is_err());
        assert!(validate_locked_api_url(Some("https://user:pass@api.example.test")).is_err());
        assert!(validate_locked_api_url(Some("https://api.example.test")).is_ok());
    }

    #[test]
    fn rejects_bootstrap_auth_failure() {
        assert!(validate_bootstrap_status(401).is_err());
        assert!(validate_bootstrap_status(403).is_err());
        assert!(validate_bootstrap_status(200).is_ok());
    }

    #[test]
    fn rejects_mismatched_or_inactive_bootstrap_identity() {
        let mut response = valid_response();
        response.machine_uuid = "other-machine".to_owned();
        assert!(validate_bootstrap_response(&response, "machine-uuid").is_err());

        let mut response = valid_response();
        response.status = "archived".to_owned();
        assert!(validate_bootstrap_response(&response, "machine-uuid").is_err());
    }

    #[test]
    fn accepts_matching_active_bootstrap_identity() {
        let response = valid_response();
        assert!(validate_bootstrap_response(&response, "machine-uuid").is_ok());
    }

    #[test]
    fn computes_existing_rustdesk_compatible_password_hash() {
        assert_eq!(
            compatible_password_hash("managed-secret", "salt01"),
            "jYpsSMobskz+aOegXVAX1Pnf+Gx9bquZv9RxAA0hT/s="
        );
    }

    #[test]
    fn rejects_auth_hash_upload_failure() {
        assert!(validate_auth_hash_status(401).is_err());
        assert!(validate_auth_hash_status(500).is_err());
        assert!(validate_auth_hash_status(200).is_ok());
        assert!(validate_auth_hash_status(204).is_ok());
    }

    #[test]
    fn ipc_timeout_exceeds_complete_bootstrap_timeout() {
        let maximum_operation_ms = MANAGED_LOCK_TIMEOUT.as_millis() as u64
            + (2 * MANAGED_HTTP_TIMEOUT.as_millis() as u64)
            + MANAGED_BODY_TIMEOUT.as_millis() as u64;
        assert!(MANAGED_IDENTITY_IPC_TIMEOUT_MS > maximum_operation_ms);
    }

    #[test]
    fn rejects_expired_bootstrap_identity() {
        let mut response = valid_response();
        response.session_expires_at = 100;
        assert!(validate_bootstrap_response_at(&response, "machine-uuid", 100).is_err());
        response.session_expires_at = 101;
        assert!(validate_bootstrap_response_at(&response, "machine-uuid", 100).is_ok());
        response.session_expires_at = 0;
        assert!(validate_bootstrap_response_at(&response, "machine-uuid", 0).is_err());
    }
}
