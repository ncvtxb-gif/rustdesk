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
    if status == 200 {
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
    if response.machine_uuid != expected_machine_uuid {
        bail!("managed device bootstrap machine UUID mismatch");
    }
    if response.status != "active" {
        bail!("managed device identity is not active");
    }
    if response.password_version == 0 {
        bail!("managed device credential version is invalid");
    }
    if response.rustdesk_id.is_empty() || response.permanent_password.is_empty() {
        bail!("managed device bootstrap response is incomplete");
    }
    Ok(())
}

pub async fn bootstrap(access_token: &str) -> ResultType<()> {
    let _bootstrap_lock = BOOTSTRAP_LOCK.lock().await;
    let _bootstrap_guard = BootstrapGuard::begin();
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
    let response = client
        .post(endpoint)
        .bearer_auth(access_token)
        .json(&ManagedDeviceBootstrapRequest {
            machine_uuid: &machine_uuid,
            platform: "windows",
        })
        .send()
        .await
        .context("managed device bootstrap request failed")?;
    validate_bootstrap_status(response.status().as_u16())?;
    let identity = response
        .json::<ManagedDeviceBootstrapResponse>()
        .await
        .context("invalid managed device bootstrap response")?;
    validate_bootstrap_response(&identity, &machine_uuid)?;
    Config::apply_managed_identity(&identity.rustdesk_id, &identity.permanent_password)?;

    let auth_hash = compatible_password_hash(&identity.permanent_password, &Config::get_salt());
    let upload_result = async {
        let auth_hash_endpoint = api_url
            .join("/api/managed-device/auth-hash")
            .context("invalid managed device auth hash endpoint")?;
        let response = client
            .put(auth_hash_endpoint)
            .bearer_auth(access_token)
            .json(&ManagedDeviceAuthHashRequest { hash: &auth_hash })
            .send()
            .await
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
    }
}
