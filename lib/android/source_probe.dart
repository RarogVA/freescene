import '../catalog/catalog_models.dart';
import '../catalog/source_checks.dart';
import 'android_runtime.dart';

SourceChecks androidSourceChecks(
  CatalogRepository repository, {
  int? Function()? season,
  int? Function()? episode,
}) {
  var epoch = 0;
  return SourceChecks(
    cancelProbe: () async {
      ++epoch;
      await AndroidRuntime.channel.invokeMethod<void>('sourceProbeCancel');
    },
    probe: (source) async {
      final generation = epoch;
      final selectedSeason = season?.call(), selectedEpisode = episode?.call();
      final resolved = await repository
          .resolve(source)
          .timeout(const Duration(seconds: 15));
      if (generation != epoch) return SourceCheckState.unavailable;
      final result = await AndroidRuntime.channel.invokeMethod<String>(
        'sourceProbe',
        {
          'season': ?selectedSeason,
          'episode': ?selectedEpisode,
          if (resolved.torrentBytes != null) 'bytes': resolved.torrentBytes,
          if (resolved.uri?.scheme == 'magnet')
            'magnet': resolved.uri.toString(),
        },
      );
      return switch (result) {
        'data' => SourceCheckState.data,
        'timeout' => SourceCheckState.timeout,
        _ => SourceCheckState.unavailable,
      };
    },
  );
}
