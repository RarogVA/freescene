import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freescene/app.dart';
import 'package:freescene/settings/preferences.dart';
import 'package:freescene/torrent/native_torrent.dart';

class LicenseNative extends NativeTorrentService {
  String? notices;
  @override
  Future<dynamic> call(String method, [Map<String, dynamic>? args]) async {
    if (method == 'showLicenses') notices = args!['text'] as String;
    if (method == 'status') return {'tasks': [], 'persistenceError': ''};
    return null;
  }
}

void main() {
  testWidgets(
    'About license request sends complete registered notices to its native window',
    (tester) async {
      final body =
          'Copyright fixture\n\n${'Full notice text. ' * 5000}\n\nEnd of notice.';
      LicenseRegistry.addLicense(() async* {
        yield LicenseEntryWithLineBreaks(['Fixture A', 'Fixture B'], body);
      });
      final native = LicenseNative();
      await tester.pumpWidget(
        FreeSceneApp(
          initialPreferences: Preferences(),
          savePreferences: (_) async {},
          nativeService: native,
        ),
      );
      await tester.pumpAndSettle();
      final response = tester.binding.defaultBinaryMessenger
          .handlePlatformMessage(
            NativeTorrentService.channel.name,
            const StandardMethodCodec().encodeMethodCall(
              const MethodCall('openLicenses'),
            ),
            null,
          );
      await tester.pumpAndSettle();
      await response;
      expect(native.notices, contains('Fixture A · Fixture B'));
      expect(native.notices, contains('Copyright fixture'));
      expect(
        native.notices,
        contains('${'Full notice text. ' * 4999}Full notice text.'),
      );
      expect(native.notices, contains('End of notice.'));
      await tester.pumpWidget(const SizedBox());
    },
  );
}
