import 'dart:io';

import 'package:flutter/services.dart';

/// Android owns its private paths; it never uses HOME or macOS's profile.
class AndroidRuntime {
  const AndroidRuntime({
    required this.profile,
    required this.cache,
    required this.tv,
    required this.lowRam,
    required this.version,
  });
  static const channel = MethodChannel('freescene/android');
  final Directory profile, cache;
  final bool tv, lowRam;
  final String version;

  static Future<AndroidRuntime> load() async {
    final data = await channel.invokeMapMethod<String, dynamic>('runtime');
    if (data == null ||
        data['profile'] is! String ||
        data['cache'] is! String ||
        !(data['profile'] as String).startsWith('/') ||
        !(data['cache'] as String).startsWith('/') ||
        data['tv'] is! bool ||
        data['lowRam'] is! bool ||
        data['version'] is! String) {
      throw const FormatException('Invalid Android runtime');
    }
    return AndroidRuntime(
      profile: Directory(data['profile'] as String),
      cache: Directory(data['cache'] as String),
      tv: data['tv'] as bool,
      lowRam: data['lowRam'] as bool,
      version: data['version'] as String,
    );
  }
}

/// Deliberate resource budgets, not a claim about measured frame rate.
class AndroidBudget {
  const AndroidBudget({required this.lite, required this.tv});
  factory AndroidBudget.forDevice(AndroidRuntime device) =>
      AndroidBudget(lite: device.lowRam || device.tv, tv: device.tv);
  final bool lite, tv;
  int get imageMemoryBytes => (lite ? 24 : 64) * 1024 * 1024;
  int get diskCacheBytes => (lite ? 64 : 128) * 1024 * 1024;
  int get posterWidth => lite ? 240 : 400;
  int get concurrentPosters => lite ? 2 : 4;
  int get pageSize => tv ? 12 : 20;
}
