import 'package:flutter/foundation.dart';

/// Uses the same registry as Flutter's license page, including bundled notices.
Future<String> collectLicenseNotices({Stream<LicenseEntry>? entries}) async {
  final text = StringBuffer();
  await for (final entry in entries ?? LicenseRegistry.licenses) {
    text.writeln(entry.packages.join(' · '));
    text.writeln('─' * 64);
    for (final paragraph in entry.paragraphs) {
      text.writeln(paragraph.text);
      text.writeln();
    }
    text.writeln();
  }
  return text.toString();
}
