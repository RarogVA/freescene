import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'android_runtime.dart';

const developerSupportUrl = 'https://pay.cloudtips.ru/p/d45d5d02';
const developerSupportQrAsset = 'assets/support/cloudtips-qr.png';

Future<void> showDeveloperSupport(
  BuildContext context, {
  required bool english,
  required bool tv,
}) async {
  String tr(String ru, String en) => english ? en : ru;
  if (!tv) {
    try {
      await AndroidRuntime.channel.invokeMethod<void>('supportDeveloper');
      return;
    } on PlatformException {
      // Keep the payment address available if Android has no browser handler.
    } on MissingPluginException {
      // An older native host can still show the address for manual opening.
    }
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        scrollable: true,
        title: Text(tr('Не удалось открыть браузер', 'Could not open browser')),
        content: const SelectableText(developerSupportUrl),
        actions: [
          TextButton(
            onPressed: () => Clipboard.setData(
              const ClipboardData(text: developerSupportUrl),
            ),
            child: Text(tr('Копировать ссылку', 'Copy link')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(tr('Закрыть', 'Close')),
          ),
        ],
      ),
    );
    return;
  }

  await showDialog<void>(
    context: context,
    builder: (ctx) {
      final qrSize = (MediaQuery.sizeOf(ctx).height * 0.5).clamp(180.0, 320.0);
      final theme = Theme.of(ctx);
      final foreground = theme.colorScheme.primary;
      final background =
          theme.dialogTheme.backgroundColor ??
          theme.colorScheme.surfaceContainerHigh;
      final instructions = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr(
              'Отсканируйте QR-код камерой телефона, чтобы поддержать развитие FreeScene.',
              'Scan the QR code with your phone camera to support FreeScene.',
            ),
          ),
          const SizedBox(height: 16),
          Text(
            tr(
              'Выберите сумму и способ оплаты на странице CloudTips.',
              'Choose an amount and payment method on the CloudTips page.',
            ),
          ),
          const SizedBox(height: 16),
          Text(developerSupportUrl, style: Theme.of(ctx).textTheme.bodyMedium),
          const SizedBox(height: 16),
          Text(
            tr(
              'Поддержка добровольная. Все возможности приложения остаются бесплатными.',
              'Support is optional. All app features remain free.',
            ),
            style: Theme.of(ctx).textTheme.bodyMedium,
          ),
        ],
      );
      final qr = ColorFiltered(
        // Map the original black/white pixels to the accent/dialog colors.
        // Keep the QR geometry and its quiet zone unchanged.
        colorFilter: ColorFilter.matrix([
          background.r - foreground.r,
          0,
          0,
          0,
          foreground.r * 255,
          0,
          background.g - foreground.g,
          0,
          0,
          foreground.g * 255,
          0,
          0,
          background.b - foreground.b,
          0,
          foreground.b * 255,
          0,
          0,
          0,
          1,
          0,
        ]),
        child: Image.asset(
          developerSupportQrAsset,
          key: const ValueKey('developer-support-qr'),
          width: qrSize,
          height: qrSize,
          filterQuality: FilterQuality.none,
          semanticLabel: tr(
            'QR-код для поддержки FreeScene',
            'Support FreeScene QR code',
          ),
        ),
      );
      return AlertDialog(
        key: const ValueKey('developer-support-dialog'),
        backgroundColor: background,
        scrollable: true,
        title: Text(
          tr('Поддержать разработчика', 'Support the developer'),
          textAlign: TextAlign.center,
        ),
        content: SizedBox(
          width: 640,
          child: MediaQuery.sizeOf(ctx).width >= 648
              ? Row(
                  children: [
                    qr,
                    const SizedBox(width: 24),
                    Expanded(child: instructions),
                  ],
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [qr, const SizedBox(height: 16), instructions],
                ),
        ),
        actions: [
          FilledButton(
            key: const ValueKey('developer-support-close'),
            autofocus: true,
            onPressed: () => Navigator.pop(ctx),
            child: Text(tr('Закрыть', 'Close')),
          ),
        ],
      );
    },
  );
}
