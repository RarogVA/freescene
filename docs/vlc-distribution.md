# VLC в FreeScene: состав дистрибутива и исходники

Поддерживаются отдельные пакеты для Apple Silicon и Intel x86_64. Для Intel используется официальный `vlc-3.0.21-intel64.dmg`, проверенный по SHA-256 `d431fd051c3dc7af02bd313c6d05d90cf604b70ed3ec5bba6fd4c49ef3e638d9`; точный состав и зависимости записаны в `validation/freescene/vlc-distribution-x86_64.json`. Исходники и contrib имеют те же версии, поэтому полный сопроводительный архив общий. При пересборке исходного VLC для Intel используйте `extras/package/macosx/build.sh -a x86_64 -c`.

При выпуске рядом с приложением размещают `FreeScene-VLC-sources.tar.gz`.
Он содержит полный исходный архив VLC 3.0.21, 13 архивов contrib, их контрольные
суммы, лицензии и этот документ. Все патчи и рецепты contrib находятся внутри
`vlc-3.0.21.tar.xz` в `contrib/src/<компонент>/`. Исходники не заменены ссылкой
на чужой сервер: архивы доступны из того же GitHub Release, что и приложение.

Бинарная база — официальный `vlc-3.0.21-arm64.dmg` VideoLAN, SHA-256
`15dd65bf6489da9ec6a67f5585c74c40a58993acff41a82958a916dd74178044`.
Проверяются libvlc, libvlccore и все 46 выбранных плагинов. Их оригинальные
байты сверяются с DMG; FreeScene меняет только rpath и локальную подпись.
Полный набор VLC и его GPL-плагины в приложение не копируются.

| Статическая зависимость | Версия | Условия | Где используется |
|---|---|---|---|
| FFmpeg | 4.4.4 | LGPL 2.1+ | avcodec, swscale; merge-ffmpeg |
| GSM | 1.0.13 | разрешительная лицензия TU Berlin | FFmpeg |
| LAME | 3.100 | LGPL 2.0+ | FFmpeg |
| OpenJPEG | 2.3.0 | BSD 2-Clause | FFmpeg |
| zlib | 1.2.13 | zlib | FFmpeg, MP4, MKV, FreeType |
| FreeType | 2.12.1 | FTL, выбран разрешительный вариант | freetype |
| GNU FriBidi | 1.0.12 | LGPL 2.1+ | freetype |
| HarfBuzz | 3.4.0 | MIT | freetype |
| libebml | 1.4.3 | LGPL 2.1+ | mkv |
| libmatroska | 1.6.3 | LGPL 2.1+ | mkv |
| SpeexDSP | 1.2.1 | BSD 3-Clause | speex_resampler |
| libdvbpsi | 1.3.3 | LGPL 2.1+ | MPEG-TS demux |
| GNU gettext libintl | 0.19.8.1 | LGPL 2.1+ | libvlccore |

Версии сопоставлены с фиксированными рецептами contrib выпуска 3.0.21;
для FFmpeg, zlib, FriBidi, HarfBuzz и OpenJPEG есть также строки версии в
выбранных бинарных файлах. В FFmpeg проверены фактическая configure-строка
и сообщения о лицензии: нет `--enable-gpl`, `--enable-version3` и
`--enable-nonfree`, есть libgsm/libopenjpeg/libmp3lame. Библиотека libintl
отличается от GPL-инструментов gettext: последние в приложение не входят.
SpeexDSP — отдельный пакет, кодек Speex в этот набор плагинов не включён.

Динамические зависимости всех 48 Mach-O проверяются через `otool -L`:
разрешены только две включённые библиотеки VLC, `/usr/lib` и системные
frameworks Apple. Зависимостей от Homebrew, установленного VLC, GnuTLS,
libgcrypt, libsamplerate, x264/x265 или других внешних dylib в этом наборе нет.
Это аудит конкретного состава, а не утверждение о лицензии всего VLC.
Битовая воспроизводимость старой сборки VideoLAN на новом Xcode не заявляется.

## HTTPS и Secure Transport

Модуль `securetransport` предоставляет TLS для доступа по HTTPS.
`modules/misc/securetransport.c` в VLC 3.0.21 содержит LGPL-2.1-or-later и
Copyright (C) 2013 David Fuhrmann. Makefile и Mach-O связывают модуль
с libvlccore и системными Apple Security/CoreFoundation.
Подпись исходного плагина принадлежит VideoLAN, Team ID `75GAHG3SZQ`;
его байты сверяются с официальным DMG.

Текущие отчёты: `validation/freescene/vlc-module-headers.json`,
`vlc-distribution-arm64.json` и `vlc-distribution-x86_64.json`.

## Изменение и пересборка

Собственный код FreeScene — MIT. Для библиотек действуют их лицензии;
отладка и reverse engineering ради изменения LGPL-библиотек не запрещены.
`licenses/VLC-THIRD-PARTY-NOTICES.txt` включён в пакет и экран лицензий.
Приложение не использует library validation/hardened runtime, препятствующий
локальной замене библиотек в этой локально подписанной сборке.

1. Распакуйте исходный VLC, затем поместите архивы contrib из этого комплекта
   в `vlc-3.0.21/contrib/tarballs/`. Рецепты сверяют SHA-512 перед сборкой.
2. Используйте `extras/package/macosx/build.sh -h` из исходного VLC. Для arm64
   укажите `-a aarch64 -c`; `-c` требует сборки contrib из исходников вместо
   скачивания готового contrib. Скрипт собирает tools, contrib, VLC и macOS bundle.
   Опции скрипта и адаптация к версии SDK описаны в самом исходном файле.
   Изменения contrib вносите до сборки в соответствующие исходники/патчи.
3. Upstream использовал `--enable-merge-ffmpeg`, т.е. avcodec/swscale включают
   статические библиотеки FFmpeg и перечисленные выше зависимости. Полные
   configure-строки upstream сохранены в отчёте аудита. Для LGPL-конфигурации
   FFmpeg не включайте GPL, version3 и nonfree. Нужные для декодера параметры:
   `--enable-static --disable-shared --enable-libgsm --enable-libopenjpeg
   --enable-libmp3lame --disable-avdevice --disable-avfilter --disable-swresample`.
   Остальные параметры и патчи задаёт `contrib/src/ffmpeg/rules.mak`.
4. Передайте своё собранное `VLC.app` в `python3 tools/build_native.py --allow-modified-vlc --vlc
   /путь/VLC.app`. Скрипт копирует только явный список модулей, меняет rpath
   на относительный и подписывает локальным ad hoc сертификатом.
5. Соберите FreeScene по README. Или замените соответствующие dylib в
   `FreeScene.app/Contents/Resources/VLC/{lib,plugins}` согласованным набором
   и выполните `codesign --force --deep --sign - /путь/FreeScene.app`.

Проверка дистрибутива: `tools/audit_vlc_distribution.py`, закреплённые архивы:
`tools/vlc-dependencies.json`. У изменённых пользователем библиотек ожидаемо
будет другой хеш; их не нужно выдавать за оригинальные бинарные файлы VideoLAN.

Часть этого ПО copyright © 2022 The FreeType Project (www.freetype.org).
Все права защищены. FreeType используется на условиях FreeType License.
This software uses libraries from the FFmpeg project under LGPL 2.1 or later.
Условия FFmpeg: https://ffmpeg.org/legal.html ; лицензия LGPL 2.1:
https://www.gnu.org/licenses/old-licenses/lgpl-2.1.html .

## MPEG-TS

Модуль `ts` взят из того же проверенного официального VLC 3.0.21. Его
исходники LGPL 2.1+, кроме `codec/opus_header.c` под BSD 2-Clause. Уведомление
Xiph, исходники libdvbpsi 1.3.3 и полный исходный VLC входят в сопроводительный
комплект. Хеши исходников и выбранных бинарных модулей закреплены в отчётах.

## Сопроводительный архив

Проверка пакета требует SHA256 сопроводительного архива, закреплённую в
`tools/verify_release_package.py`. Если архив пересоздан, сначала проверяют его
полный состав и затем обновляют закреплённую сумму перед выпуском.
