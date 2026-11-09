import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../settings/license_document.dart';
import 'android_runtime.dart';

/// Metadata only; the native layer verifies and retains the downloaded APK.
class AndroidUpdates {
  Future<Map<dynamic, dynamic>> call(
    String method, [
    Map<String, dynamic>? args,
  ]) async =>
      await AndroidRuntime.channel.invokeMapMethod<dynamic, dynamic>(
        method,
        args,
      ) ??
      {};
  Future<Map<dynamic, dynamic>> check() => call('updateCheck');
}

class AndroidAboutDialog extends StatefulWidget {
  const AndroidAboutDialog({
    required this.version,
    required this.english,
    this.tv = false,
    this.offeredVersion,
    super.key,
  });
  final String version;
  final bool english;
  final bool tv;
  final String? offeredVersion;
  @override
  State<AndroidAboutDialog> createState() => _AndroidAboutDialogState();
}

class _AndroidAboutDialogState extends State<AndroidAboutDialog> {
  final updates = AndroidUpdates();
  final primaryAction = FocusNode();
  bool initialFocusDelivered = false;
  bool busy = false, ready = false;
  String? operation;
  String? available, status;
  String tr(String ru, String en) => widget.english ? en : ru;
  @override
  void initState() {
    super.initState();
    available = widget.offeredVersion;
  }

  @override
  void dispose() {
    primaryAction.dispose();
    super.dispose();
  }

  Future<void> request(Future<void> Function() run) async {
    final previousFocus = FocusManager.instance.primaryFocus;
    setState(() {
      busy = true;
      status = null;
    });
    try {
      await run();
    } catch (e) {
      if (mounted) {
        status = tr(switch (e is PlatformException ? e.code : '') {
          'github_access' =>
            'Выпуски FreeScene сейчас недоступны. Повторите позже.',
          'signature_or_version' =>
            'Подпись или версия APK не подходит. Установка отменена.',
          'invalid_apk' => 'Проверка файла обновления не пройдена.',
          'installer' => 'Системный установщик недоступен.',
          _ => 'Не удалось выполнить обновление. Проверьте сеть и повторите.',
        }, 'Update unavailable. Check the connection and try again.');
      }
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
          operation = null;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !widget.tv) return;
          if (initialFocusDelivered &&
              previousFocus?.context != null &&
              previousFocus!.canRequestFocus) {
            previousFocus.requestFocus();
          } else if (primaryAction.context != null) {
            initialFocusDelivered = true;
            primaryAction.requestFocus();
          }
        });
      }
    }
  }

  Widget action(
    String id,
    String label,
    VoidCallback? run, {
    bool primary = false,
  }) => FilledButton(
    key: ValueKey('android-about-$id'),
    focusNode: primary ? primaryAction : null,
    autofocus: widget.tv && primary,
    style: FilledButton.styleFrom(
      minimumSize: const Size(0, 64),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    ),
    onPressed: busy ? null : run,
    child: Text(label, textAlign: TextAlign.center),
  );

  Future<void> check() => request(() async {
    setState(() => operation = tr('Проверка…', 'Checking…'));
    final data = await updates.check();
    available = data['available'] == true ? data['version'] as String? : null;
    ready = false;
    if (available == null) {
      status = tr('Новых Android-сборок нет.', 'No new Android builds.');
    }
  });

  Future<void> install() => request(() async {
    if (!ready) {
      setState(() {
        operation = tr('Загрузка…', 'Downloading…');
        status = tr(
          'Скачивание и проверка обновления…',
          'Downloading and verifying update…',
        );
      });
      ready = (await updates.call('updateDownload'))['ready'] == true;
      if (!ready) throw PlatformException(code: 'invalid_apk');
    }
    if (!mounted) return;
    setState(() => operation = tr('Установка…', 'Installing…'));
    final data = await updates.call('updateInstall');
    status = data['permissionRequired'] == true
        ? tr(
            'Разрешите установку для FreeScene, вернитесь и нажмите «Установить» ещё раз.',
            'Allow installs for FreeScene, return and press Install again.',
          )
        : tr(
            'Подтвердите установку в системном окне Android.',
            'Confirm installation in Android.',
          );
  });

  Future<void> licenses() async {
    final notices = await collectLicenseNotices();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        scrollable: true,
        title: Text(tr('Лицензии открытого ПО', 'Open-source licenses')),
        content: SizedBox(width: 560, child: Text(notices)),
        actions: [
          FilledButton(
            autofocus: widget.tv,
            onPressed: () => Navigator.pop(ctx),
            child: Text(tr('Закрыть', 'Close')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = (MediaQuery.sizeOf(context).width - 128).clamp(180.0, 560.0);
    final controls = [
      action(
        'check',
        operation ??
            (available == null
                ? tr('Проверить обновления', 'Check for updates')
                : tr('Установить обновления', 'Install updates')),
        available == null ? check : install,
        primary: true,
      ),
      action(
        'licenses',
        tr('Лицензии открытого ПО', 'Open-source licenses'),
        licenses,
      ),
    ];
    return AlertDialog(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      scrollable: true,
      title: Row(
        children: [
          Expanded(
            child: Text(
              widget.offeredVersion == null
                  ? tr('О приложении', 'About')
                  : tr(
                      'Доступно обновление FreeScene',
                      'FreeScene update available',
                    ),
            ),
          ),
          IconButton(
            key: const ValueKey('android-about-close'),
            tooltip: tr('Закрыть', 'Close'),
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
      content: SizedBox(
        width: width,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('assets/branding/app-icon.png', width: 64, height: 64),
            const SizedBox(height: 8),
            Text(
              'FreeScene',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            Text('${tr('Версия', 'Version')} ${widget.version}'),
            const SizedBox(height: 12),
            Text(
              tr(
                'FreeScene — портал для Вашего удобства!',
                'FreeScene — a portal for your convenience!',
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            if (busy) const LinearProgressIndicator(),
            if (status != null)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(status!, textAlign: TextAlign.center),
              ),
            if (available != null)
              Text('${tr('Доступна версия', 'New version')} $available'),
          ],
        ),
      ),
      actions: [
        SizedBox(
          key: const ValueKey('android-about-actions'),
          width: width,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var index = 0; index < controls.length; index++) ...[
                if (index > 0) const SizedBox(height: 10),
                SizedBox(width: double.infinity, child: controls[index]),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
