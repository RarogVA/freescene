import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// TV voice capture has no editable field or second search button.
class VoiceSearchDialog extends StatefulWidget {
  const VoiceSearchDialog({
    required this.english,
    required this.listen,
    required this.cancel,
    required this.events,
    this.desktop = false,
    this.openSettings,
    super.key,
  });

  final bool english, desktop;
  final Future<String?> Function() listen;
  final Future<void> Function() cancel;
  final Stream<dynamic> events;
  final Future<void> Function()? openSettings;

  @override
  State<VoiceSearchDialog> createState() => _VoiceSearchDialogState();
}

class _VoiceSearchDialogState extends State<VoiceSearchDialog>
    with SingleTickerProviderStateMixin {
  late final pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
    lowerBound: .85,
    upperBound: 1,
  );
  StreamSubscription<dynamic>? subscription;
  final retryFocus = FocusNode(debugLabel: 'voice-retry');
  String phase = 'preparing', partial = '';
  String? error, errorCode;
  bool openingSettings = false;
  double level = 0;
  bool active = false, closed = false;
  int generation = 0;
  String tr(String ru, String en) => widget.english ? en : ru;

  @override
  void initState() {
    super.initState();
    subscription = widget.events.listen(
      _event,
      onError: (Object _) {
        // The method result carries recognition failures. A missing meter event
        // must not discard a successfully recognized query.
      },
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !closed) _start();
    });
  }

  void _event(dynamic event) {
    if (!mounted || closed || !active || event is! Map) return;
    setState(() {
      if (event['phase'] is String) phase = event['phase'] as String;
      if (event['partial'] is String) partial = event['partial'] as String;
      if (event['level'] is num) {
        level = (event['level'] as num).toDouble().clamp(0, 1);
      }
    });
    if (phase == 'listening') {
      if (!MediaQuery.disableAnimationsOf(context) && !pulse.isAnimating) {
        pulse.repeat(reverse: true);
      }
    } else {
      pulse.stop();
    }
  }

  Future<void> _start() async {
    if (active || closed) return;
    final attempt = ++generation;
    setState(() {
      active = true;
      error = null;
      errorCode = null;
      phase = 'preparing';
      partial = '';
      level = 0;
    });
    try {
      final text = await widget.listen();
      if (!mounted || closed || generation != attempt) return;
      active = false;
      final query = text?.trim();
      if (query != null && query.isEmpty) {
        throw PlatformException(code: 'voice_no_match');
      }
      closed = true;
      Navigator.pop(context, query);
    } catch (failure) {
      if (!mounted || closed || generation != attempt) return;
      pulse.stop();
      setState(() {
        active = false;
        errorCode = failure is PlatformException
            ? failure.code
            : 'voice_unavailable';
        error = _error(errorCode!);
      });
      retryFocus.requestFocus();
    }
  }

  String _error(String code) => switch (code) {
    'voice_dictation_disabled' => tr(
      'В macOS отключена Диктовка. Включите её в «Системные настройки → Клавиатура → Диктовка», затем повторите поиск. Разрешение на микрофон — отдельная настройка.',
      'Dictation is turned off in macOS. Enable it in System Settings → Keyboard → Dictation, then retry. Microphone permission is a separate setting.',
    ),
    'voice_assets_missing' => tr(
      'В macOS не загружены файлы распознавания для этого языка. Добавьте язык в «Клавиатура → Диктовка» и дождитесь загрузки, затем повторите поиск.',
      'Speech recognition files for this language are not installed. Add the language in Keyboard → Dictation, wait for the download, then retry.',
    ),
    'voice_permission' =>
      widget.desktop
          ? tr(
              'Разрешите микрофон и распознавание речи для FreeScene в системных настройках macOS.',
              'Allow microphone and speech recognition for FreeScene in macOS System Settings.',
            )
          : tr(
              'Нет доступа к микрофону. Разрешите его в настройках Android и повторите.',
              'Microphone access is denied. Allow it in Android settings and retry.',
            ),
    'voice_no_match' => tr(
      'Не удалось расслышать. Попробуйте ещё раз.',
      'Could not hear you. Please try again.',
    ),
    'voice_audio' =>
      widget.desktop
          ? tr(
              'Не удалось включить микрофон. Проверьте выбранный вход звука в macOS.',
              'Could not start the microphone. Check the selected sound input in macOS.',
            )
          : tr(
              'Не удалось включить микрофон пульта. Проверьте его подключение.',
              'Could not start the remote microphone. Check its connection.',
            ),
    'voice_network' => tr(
      'Сервис распознавания не отвечает. Проверьте интернет и повторите.',
      'The speech service is not responding. Check your connection and retry.',
    ),
    'voice_timeout' => tr(
      'Время ожидания истекло. Попробуйте ещё раз.',
      'Voice search timed out. Please try again.',
    ),
    'busy' || 'voice_busy' => tr(
      'Микрофон занят. Повторите через несколько секунд.',
      'The microphone is busy. Retry in a few seconds.',
    ),
    _ =>
      widget.desktop
          ? tr(
              'Распознавание речи недоступно на этом Mac. Повторите попытку или введите запрос.',
              'Speech recognition is unavailable on this Mac. Retry or type your search.',
            )
          : tr(
              'Голосовой ввод недоступен. Проверьте, что на ТВ включён сервис распознавания речи.',
              'Voice input unavailable. Check that a speech recognition service is enabled on the TV.',
            ),
  };

  Future<void> _openSettings() async {
    if (openingSettings || widget.openSettings == null) return;
    setState(() => openingSettings = true);
    try {
      await widget.openSettings!();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              tr(
                'Откройте «Системные настройки → Клавиатура → Диктовка» вручную.',
                'Open System Settings → Keyboard → Dictation manually.',
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => openingSettings = false);
    }
  }

  void _stop() {
    closed = true;
    generation++;
    if (!active) return;
    active = false;
    unawaited(_cancel());
  }

  Future<void> _cancel() async {
    try {
      await widget.cancel();
    } catch (_) {
      // Closing the route must remain possible even if the Activity is gone.
    }
  }

  @override
  void dispose() {
    _stop();
    unawaited(subscription?.cancel());
    pulse.dispose();
    retryFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final status = switch (phase) {
      'permission' => tr(
        'Разрешите доступ к микрофону',
        'Allow microphone access',
      ),
      'listening' => tr('Говорите…', 'Listening…'),
      'recognizing' => tr('Распознаю…', 'Recognizing…'),
      _ => tr('Подключаю микрофон…', 'Connecting microphone…'),
    };
    final color = Theme.of(context).colorScheme.primary;
    return PopScope<String>(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _stop();
      },
      child: AlertDialog(
        title: Text(tr('Голосовой поиск', 'Voice search')),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ScaleTransition(
                scale: MediaQuery.disableAnimationsOf(context)
                    ? const AlwaysStoppedAnimation(1.0)
                    : pulse,
                child: Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color.withValues(alpha: .18),
                  ),
                  child: Icon(
                    error == null ? Icons.mic : Icons.mic_off,
                    size: 48,
                    color: color,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                error ?? status,
                textAlign: TextAlign.center,
                semanticsLabel: error ?? status,
              ),
              if (error == null) ...[
                const SizedBox(height: 16),
                LinearProgressIndicator(
                  key: const ValueKey('voice-level'),
                  value: phase == 'listening' ? level : null,
                  minHeight: 5,
                ),
                if (partial.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(
                      partial,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ],
          ),
        ),
        actions: [
          if (widget.desktop &&
              widget.openSettings != null &&
              (errorCode == 'voice_dictation_disabled' ||
                  errorCode == 'voice_assets_missing'))
            FilledButton.icon(
              key: const ValueKey('voice-settings'),
              onPressed: openingSettings ? null : _openSettings,
              icon: const Icon(Icons.settings_outlined),
              label: Text(tr('Открыть настройки', 'Open Settings')),
            ),
          if (error != null)
            FilledButton(
              key: const ValueKey('voice-retry'),
              focusNode: retryFocus,
              onPressed: _start,
              child: Text(tr('Повторить', 'Retry')),
            ),
          TextButton(
            key: const ValueKey('voice-cancel'),
            autofocus: true,
            onPressed: () {
              _stop();
              Navigator.pop(context);
            },
            child: Text(tr('Отмена', 'Cancel')),
          ),
        ],
      ),
    );
  }
}
