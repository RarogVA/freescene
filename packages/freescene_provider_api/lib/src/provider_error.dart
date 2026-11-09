import 'source.dart';

abstract interface class ProviderError implements Exception {
  String label(bool english);
}

class ProviderFailure implements ProviderError {
  const ProviderFailure(this.provider, this.code, {this.status});
  final SourceProvider provider;
  final String code;
  final int? status;
  @override
  String label(bool en) {
    final reason = switch (code) {
      'challenge' =>
        en
            ? 'The website requires browser verification.'
            : 'Сайт запросил проверку браузера.',
      'link' =>
        en
            ? 'Invalid public video or playlist URL.'
            : 'Нужна публичная ссылка на видео или плейлист.',
      'subscription' =>
        en
            ? 'This title requires access on the provider website.'
            : 'Для этого видео нужен доступ на сайте провайдера.',
      'unavailable' =>
        en
            ? 'The provider did not return publicly available video. Retry later.'
            : 'Провайдер не вернул общедоступное видео. Повторите позже.',
      'noStream' =>
        en
            ? 'The provider did not return a supported public stream.'
            : 'Провайдер не вернул доступный прямой поток или embed.',
      'drm' =>
        en
            ? 'This stream requires the provider’s protected player.'
            : 'Для этого потока нужен защищённый плеер провайдера.',
      'cancelled' => en ? 'Request cancelled.' : 'Запрос отменён.',
      'timeout' =>
        en
            ? 'The service did not respond in time. Retry.'
            : 'Сервис не ответил вовремя. Повторите запрос.',
      'http' =>
        en
            ? 'The service returned HTTP $status.'
            : 'Сервис вернул HTTP $status.',
      'invalid' =>
        en
            ? 'Unexpected catalogue response.'
            : 'Не удалось прочитать ответ каталога.',
      _ =>
        en
            ? 'Could not connect. Retry.'
            : 'Не удалось подключиться. Повторите запрос.',
    };
    return '${provider.label}: $reason';
  }
}
