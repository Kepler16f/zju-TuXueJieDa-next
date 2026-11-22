import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/consent_service.dart';

/// 首次启动的全屏隐私授权页。
///
/// 用户必须阅读并勾选《隐私政策》与《用户协议》后才能进入应用；
/// 不同意则退出应用。协议全文通过系统浏览器（原生 url_launcher）打开。
class ConsentPage extends StatefulWidget {
  const ConsentPage({super.key, required this.onAgreed});

  /// 用户同意后回调（应用据此进入主界面）。
  final Future<void> Function() onAgreed;

  @override
  State<ConsentPage> createState() => _ConsentPageState();
}

class _ConsentPageState extends State<ConsentPage> {
  bool _checked = false;
  bool _busy = false;

  Future<void> _open(String url) async {
    final ok = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无法打开链接，请检查系统浏览器设置。')),
      );
    }
  }

  Future<void> _agree() async {
    if (!_checked || _busy) return;
    setState(() => _busy = true);
    await ConsentService().agree();
    if (!mounted) return;
    await widget.onAgreed();
  }

  void _decline() {
    // 不同意即退出应用（原生退出，不保留后台运行）
    exit(0);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.architecture_rounded,
                          size: 26,
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '图学习题解答',
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              '欢迎使用 · 请先阅读并同意以下条款',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  _Section(
                    title: '我们如何处理你的信息',
                    body: '本应用是完全本地运行的学习工具：题目内容内置在安装包中，'
                        '你的收藏、便签与学习进度只保存在本机，不会上传到任何服务器，'
                        '也不会收集账号、设备标识或位置信息。',
                  ),
                  _Section(
                    title: '网络与权限',
                    body: '仅当你主动点击"检查更新"或后台下载更新包时才会访问网络，'
                        '并按需申请通知权限；不申请通讯录、位置、相机等权限。',
                  ),
                  _Section(
                    title: '你的权利',
                    body: '你可以在应用内随时查看、编辑或清空收藏、便签与进度'
                        '（设置 → 学习数据），也可以通过卸载应用彻底删除全部本地数据。',
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _open(ConsentService.privacyPolicyUrl),
                          icon: const Icon(Icons.privacy_tip_outlined, size: 17),
                          label: const Text('隐私政策'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _open(ConsentService.userAgreementUrl),
                          icon: const Icon(Icons.description_outlined, size: 17),
                          label: const Text('用户协议'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  TextButton.icon(
                    onPressed: () => _open(ConsentService.homeUrl),
                    icon: const Icon(Icons.open_in_new_rounded, size: 15),
                    label: const Text('在浏览器中查看完整条款'),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerLow,
                border: Border(
                  top: BorderSide(color: theme.colorScheme.outlineVariant),
                ),
              ),
              child: Column(
                children: [
                  // 用 InkWell + Checkbox 组合（ListTile 在带背景容器中会触发
                  // Material 背景断言）。
                  InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => setState(() => _checked = !_checked),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          Checkbox(
                            value: _checked,
                            onChanged: (v) =>
                                setState(() => _checked = v ?? false),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              '我已阅读并同意《隐私政策》与《用户协议》',
                              style: const TextStyle(fontSize: 14),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _busy ? null : _decline,
                          // 窄屏（手机竖屏）下 flex:1 的空间放不下五个字会换行，
                          // FittedBox 强制单行并按需缩小字号。
                          child: const FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text('拒绝并退出', maxLines: 1, softWrap: false),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: FilledButton(
                          onPressed: (_checked && !_busy) ? _agree : null,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(_busy ? '正在进入…' : '同意并继续', maxLines: 1, softWrap: false),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            body,
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.6),
          ),
        ],
      ),
    );
  }
}
