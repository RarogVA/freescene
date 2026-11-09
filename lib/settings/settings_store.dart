import 'dart:convert';
import 'dart:io';

import 'preferences.dart';

/// Own application profile only.
class SettingsStore {
  SettingsStore(this.directory);
  final Directory directory;
  Future<void> _pendingWrite = Future.value();

  factory SettingsStore.application() {
    final override = Platform.environment['FREESCENE_DATA'];
    final home = Platform.environment['HOME'];
    if (override != null && override.isNotEmpty) {
      return SettingsStore(Directory(override));
    }
    if (home == null || home.isEmpty) {
      throw const FileSystemException('Home directory is unavailable');
    }
    return SettingsStore(
      Directory('$home/Library/Application Support/FreeScene'),
    );
  }

  File get _file => File('${directory.path}/settings.json');

  Future<Preferences> load() async {
    if (!await _file.exists()) return Preferences();
    final json = jsonDecode(await _file.readAsString());
    if (json is! Map<String, dynamic>) {
      throw const FormatException('Invalid settings document');
    }
    return Preferences.fromJson(json);
  }

  Future<void> save(Preferences value) {
    final write = _pendingWrite.then((_) async {
      await directory.create(recursive: true);
      final temporary = File('${_file.path}.tmp');
      await temporary.writeAsString(
        '${jsonEncode(value.toJson())}\n',
        flush: true,
      );
      await temporary.rename(_file.path);
    });
    // Keep the queue usable after a failed write; the caller still receives
    // that write's error and can show it to the user.
    _pendingWrite = write.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return write;
  }
}
