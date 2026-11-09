import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'android_runtime.dart';

/// TV voice capture has no editable field or second search button.
class AndroidVoiceDialog extends StatefulWidget {
  const AndroidVoiceDialog({
    required this.english,
    this.listen,
    this.cancel,
    this.events,
    super.key,
  });

  final bool english;
  final Future<String?> Function()? listen;
  final Future<void> Function()? cancel;
  final Stream<dynamic>? events;

  @override
  State<AndroidVoiceDialog> createState() => _AndroidVoiceDialogState();
}

class _AndroidVoiceDialogState extends State<AndroidVoiceDialog>
    with SingleTickerProviderStateMixin {
  // A dismissed route can still be animating when the next one opens. Share
  // one native subscription so its disposal cannot cancel the next meter.
  static final nativeEvents = const EventChannel('freescene/voice')
      .receiveBroadcastStream();
  late final pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
    lowerBound: .85,
    upperBound: 1,
  );
  StreamSubscription<dynamic>? subscription;
  final retryFocus = FocusNode(debugLabel: 'voice-retry');
  String phase = 'preparing', partial = '';
  String? error;
  double level = 0;
  bool active = false, closed = false;
  int generation = 0;
  String tr(String ru, String en) => widget.english ? en : ru;

  @override
  void initState() {
    super.initState();
    final events =
        widget.events ??
        (widget.listen == null ? nativeEvents : const Stream<dynamic>.empty());
    subscription = events.listen(
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
      if (!pulse.isAnimating) pulse.repeat(reverse: true);
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
      phase = 'preparing';
      partial = '';
      level = 0;
    });
    try {
      final text =
          await (widget.listen?.call() ??
              AndroidRuntime.channel.invokeMethod<String>('voiceListen', {
                'language': widget.english ? 'en-US' : 'ru-RU',
              }));
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
        error = _error(
          failure is PlatformException ? failure.code : 'voice_unavailable',
        );
      });
      retryFocus.requestFocus();
    }
  }

  String _error(String code) => switch (code) {
    'voice_permission' => tr(
      'Нет доступа к микрофону. Разрешите его в настройках Android и повторите.',
      'Microphone access is denied. Allow it in Android settings and retry.',
    ),
    'voice_no_match' => tr(
      'Не удалось расслышать. Попробуйте ещё раз.',
      'Could not hear you. Please try again.',
    ),
    'voice_audio' => tr(
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
    _ => tr(
      'Голосовой ввод недоступен. Проверьте, что на ТВ включён сервис распознавания речи.',
      'Voice input unavailable. Check that a speech recognition service is enabled on the TV.',
    ),
  };

  void _stop() {
    closed = true;
    generation++;
    if (!active) return;
    active = false;
    unawaited(_cancel());
  }

  Future<void> _cancel() async {
    try {
      if (widget.cancel != null) {
        await widget.cancel!();
      } else if (widget.listen == null) {
        await AndroidRuntime.channel.invokeMethod<void>('voiceCancel');
      }
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
                scale: pulse,
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
