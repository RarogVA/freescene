import 'dart:async';

import '../widgets/voice_search_dialog.dart';
import 'android_runtime.dart';

import 'package:flutter/services.dart';

class AndroidVoiceDialog extends VoiceSearchDialog {
  AndroidVoiceDialog({
    required super.english,
    Future<String?> Function()? listen,
    Future<void> Function()? cancel,
    Stream<dynamic>? events,
    super.key,
  }) : super(
         listen:
             listen ??
             (() => AndroidRuntime.channel.invokeMethod<String>('voiceListen', {
               'language': english ? 'en-US' : 'ru-RU',
             })),
         cancel:
             cancel ??
             (() async {
               if (listen == null) {
                 await AndroidRuntime.channel.invokeMethod<void>('voiceCancel');
               }
             }),
         events:
             events ??
             (listen == null ? nativeEvents : const Stream<dynamic>.empty()),
       );
  // Share the subscription while an old dialog is finishing its exit animation.
  static final nativeEvents = const EventChannel('freescene/voice')
      .receiveBroadcastStream();
}
