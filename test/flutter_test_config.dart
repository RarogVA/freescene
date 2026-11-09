import 'dart:async';

import 'package:freescene_provider_api/freescene_provider_api.dart';
import 'package:freescene/providers/demo.dart';

Future<void> testExecutable(FutureOr<void> Function() main) async {
  ProviderSetup.install(demoProviders);
  await main();
}
