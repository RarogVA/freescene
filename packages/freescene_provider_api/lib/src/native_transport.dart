import 'package:flutter/services.dart';

class NativeProviderTransport {
  const NativeProviderTransport();
  static const channel = MethodChannel('freescene/providers');
  Future<dynamic> call(String method, [Map<String, dynamic>? args]) =>
      channel.invokeMethod<dynamic>(method, args);
}
