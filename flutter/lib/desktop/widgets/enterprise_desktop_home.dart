import 'package:flutter/material.dart';

const enterpriseRemoteCardKey = Key('enterprise-remote-card');
const enterpriseLocalIdCardKey = Key('enterprise-local-id-card');
const enterprisePeerContentKey = Key('enterprise-peer-content');

class EnterpriseDesktopHomeLayout extends StatelessWidget {
  const EnterpriseDesktopHomeLayout({
    super.key,
    required this.remoteCard,
    required this.localIdCard,
    required this.peerContent,
    required this.statusBar,
  });

  final Widget remoteCard;
  final Widget localIdCard;
  final Widget peerContent;
  final Widget statusBar;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
                child: SizedBox(
                  height: 220,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        key: enterpriseRemoteCardKey,
                        child: remoteCard,
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        key: enterpriseLocalIdCardKey,
                        child: localIdCard,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Divider(height: 1),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: SizedBox.expand(
                    key: enterprisePeerContentKey,
                    child: peerContent,
                  ),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        statusBar,
      ],
    );
  }
}

class EnterpriseLocalIdCard extends StatelessWidget {
  const EnterpriseLocalIdCard({
    super.key,
    required this.idController,
    required this.onCopy,
  });

  final TextEditingController idController;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final textColor = Theme.of(context).textTheme.titleLarge?.color;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 22),
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.all(Radius.circular(13)),
        border: Border.all(color: Theme.of(context).colorScheme.surface),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('你的桌面', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 10),
          Text(
            '你的桌面可以通过下面的 ID 进行远程访问。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const Spacer(),
          Container(
            height: 57,
            decoration: const BoxDecoration(
              border: Border(
                left: BorderSide(width: 2, color: Color(0xFF0071FF)),
              ),
            ),
            padding: const EdgeInsets.only(left: 9),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ID',
                  style: TextStyle(
                    fontSize: 14,
                    color: textColor?.withOpacity(0.5),
                  ),
                ),
                const SizedBox(height: 4),
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: idController,
                  builder: (context, value, child) => GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onDoubleTap: onCopy,
                    child: Text(
                      value.text,
                      style: const TextStyle(fontSize: 22),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
