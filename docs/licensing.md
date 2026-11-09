# Лицензирование FreeScene

Собственный код распространяется по **MIT**, Copyright © 2026 Rar0g.
Корневой `LICENSE` включён в ресурсы приложения и доступен через
«О приложении» → «Лицензии открытого ПО».

Для хешей файлов кеша используется `crypto` 3.0.7 с `typed_data` 1.4.0
(BSD-3-Clause). Уведомления зависимостей доступны в стандартном экране
лицензий Flutter и ресурсе NOTICES сборки.

В `licenses/` сохранены тексты лицензий Flutter, Dart, intl, Material Icons,
libtorrent 2.1.2, OpenSSL 3.5.9, Boost, nlohmann/json, try_signal и libVLC 3.0.21.
Их тексты включаются в сборку и экран лицензий.

| Компонент | Условия и состояние |
|---|---|
| Код FreeScene | MIT; корневой `LICENSE` |
| Flutter | BSD-3-Clause для framework; engine и зависимости имеют дополнительные уведомления |
| AndroidX Media3 1.11.1, WebKit 1.17.1 и AndroidX | Apache-2.0; только Android, текст включён в `licenses/AndroidX-Media3-LICENSE.txt` |
| libtorrent-rasterbar | BSD; включён в нативный движок |
| libVLC | LGPL-2.1-or-later; проверены два dylib, 46 выбранных модулей и 13 статических contrib-зависимостей; исходники и уведомления должны сопровождать бинарный Release |
| Material Icons | Apache-2.0; сохранить уведомления в дистрибутиве |

LGPL libVLC не назначает автоматически LGPL всему собственному коду. При распространении нужно выполнять требования LGPL к библиотеке и её изменениям, уведомлениям, соответствующему исходному коду и возможности использования изменённой версии библиотеки. Окончательные обязанности зависят от способа связывания и состава пакета.

Часть модулей VLC остаётся под GPL. Для новой сборки нужен перечень реально включённых dylib/модулей с версиями, лицензиями и исходниками. До такого перечня готовый `.app` нельзя объявлять целиком MIT или LGPL-only.

Подключение к внешнему сервису не даёт права распространять его код и ресурсы; условия сервисов рассматриваются отдельно от лицензии программы. MIT собственного кода не отменяет лицензий зависимостей.

Официальные источники:

- Flutter: https://docs.flutter.dev/resources/faq
- libtorrent: https://www.libtorrent.org/
- libVLC и перелицензирование модулей: https://images.videolan.org/press/lgpl-modules.html
- Текст LGPL 2.1: https://www.gnu.org/licenses/old-licenses/lgpl-2.1.html
- Выбор лицензии репозитория: https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/licensing-a-repository

Выбранные модули и SHA-256 исходных бинарных файлов записываются в
`Contents/Resources/VLC/modules.json`. Заголовки 46 модулей проверены в
`validation/freescene/vlc-module-headers.json`; текущие бинарные аудиты —
`vlc-distribution-arm64.json` и `vlc-distribution-x86_64.json` в той же папке.
Модуль `securetransport` использует системные Apple Security/CoreFoundation.
GPL-contrib libsamplerate не включается. [Состав и пересборка](vlc-distribution.md).
Контрольные суммы архивов contrib закреплены в `tools/vlc-dependencies.json`;
`tools/package_vlc_sources.py` подготавливает комплект исходников для размещения
рядом с бинарным файлом. Проверка состава не является аудитом уязвимостей VLC.

## Play

Play Regular и Bold включены без изменений из официального Google Fonts, commit `51c6a423fbfbd78a5111241dfd07791644b4c5c6`. Шрифт распространяется под SIL Open Font License 1.1, с правом встраивания в приложение при сохранении уведомления и лицензии. Текст включён в `licenses/Play-OFL.txt`, пакет приложения и экран лицензий. Источники и SHA-256: `validation/freescene/play-fonts.json`.
