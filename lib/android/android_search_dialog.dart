import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'android_runtime.dart';

class AndroidSearchDialog extends StatefulWidget {
  const AndroidSearchDialog({
    required this.initial,
    required this.english,
    this.voice,
    this.startVoice = false,
    this.initialError,
    this.allowVoice = true,
    this.label,
    super.key,
  });
  final String initial;
  final bool english;
  final Future<String?> Function()? voice;
  final bool startVoice;
  final bool allowVoice;
  final String? label;
  final String? initialError;
  @override
  State<AndroidSearchDialog> createState() => _AndroidSearchDialogState();
}

class _AndroidSearchDialogState extends State<AndroidSearchDialog> {
  late final text = TextEditingController(text: widget.initial);
  final input = FocusNode(debugLabel: 'search-input');
  bool listening = false;
  late String? error = widget.initialError;
  String tr(String ru, String en) => widget.english ? en : ru;
  @override
  void initState() {
    super.initState();
    if (widget.startVoice) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _voice();
      });
    }
  }

  @override
  void dispose() {
    text.dispose();
    input.dispose();
    super.dispose();
  }

  Future<void> _voice() async {
    if (listening) return;
    setState(() {
      listening = true;
      error = null;
    });
    try {
      final result =
          await (widget.voice?.call() ??
              AndroidRuntime.channel.invokeMethod<String>('voiceSearch', {
                'language': widget.english ? 'en-US' : 'ru-RU',
              }));
      if (!mounted) return;
      if (result != null && result.trim().isNotEmpty) {
        text.text = result.trim();
        text.selection = TextSelection.collapsed(offset: text.text.length);
      }
    } on PlatformException catch (failure) {
      if (mounted) {
        error = failure.code == 'voice_permission'
            ? tr(
                'Разрешите доступ к микрофону для голосового поиска. Пока можно ввести запрос вручную.',
                'Allow microphone access for voice search, or type your search.',
              )
            : tr(
                'Голосовой ввод недоступен. Введите запрос вручную.',
                'Voice input unavailable. Type your search.',
              );
      }
    } catch (_) {
      if (mounted) {
        error = tr(
          'Не удалось распознать речь. Повторите или введите запрос.',
          'Could not recognize speech. Retry or type your search.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => listening = false);
        input.requestFocus();
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: Text(widget.label ?? tr('Поиск', 'Search')),
    content: SizedBox(
      width: 480,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const ValueKey('android-search-input'),
            controller: text,
            focusNode: input,
            autofocus: true,
            textInputAction: TextInputAction.search,
            maxLength: 250,
            onSubmitted: (value) => Navigator.pop(context, value.trim()),
            decoration: InputDecoration(
              labelText:
                  widget.label ??
                  tr('Название фильма или сериала', 'Film or series title'),
              suffixIcon: IconButton(
                key: const ValueKey('android-search-clear'),
                tooltip: tr('Очистить', 'Clear'),
                icon: const Icon(Icons.close),
                onPressed: () {
                  text.clear();
                  input.requestFocus();
                },
              ),
            ),
          ),
          if (widget.allowVoice) const SizedBox(height: 12),
          if (widget.allowVoice)
            FilledButton.icon(
              key: const ValueKey('android-voice-search'),
              onPressed: listening ? null : _voice,
              icon: const Icon(Icons.mic),
              label: Text(
                listening
                    ? tr('Слушаю…', 'Listening…')
                    : tr('Голосовой поиск', 'Voice search'),
              ),
            ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(error!),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(tr('Отмена', 'Cancel')),
      ),
      FilledButton(
        key: const ValueKey('android-search-submit'),
        onPressed: () => Navigator.pop(context, text.text.trim()),
        child: Text(tr('Найти', 'Search')),
      ),
    ],
  );
}
