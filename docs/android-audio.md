# Программный декодер звука Android / TV

На Android и телевизорах без системных AC3, E-AC3 и DTS Media3 может показывать
видео без звука и «Аудио: Нет». Добавлен официальный FFmpeg-модуль Media3 1.11.1.
Системные декодеры сохраняют приоритет; FFmpeg используется для неподдерживаемых
форматов. Видео по-прежнему декодируется через Android MediaCodec.

Включены только аудиодекодеры `ac3`, `eac3`, `dca` и преобразование PCM.
Нет FFmpeg-видео, кодировщиков, контейнеров и сетевых протоколов.
Если известные аудиодорожки всё равно не поддерживаются, плеер сообщает об этом
вместо молчаливого воспроизведения. Видео без аудиодорожек предупреждения не вызывает.

Обычная сборка `python3 tools/build_android.py --flavor tv --preview` готовит
декодер автоматически для ARM32 и ARM64, начиная с Android API 24.
Для отдельной сборки: `python3 tools/build_android_audio.py --sdk /path/to/sdk`.
Нужны NDK 28.2.13676358, Python 3.9+, curl и make на Linux или macOS.
Для прямого `flutter build` сначала выполните этот скрипт, как и сборку движка.
Загруженные исходники и выходные файлы находятся только в `build/android-audio/`.
Каждый исходный файл сверяется с SHA-256 из `tools/android-audio-dependencies.json`.
Версию Media3 в манифесте нужно обновлять вместе с зависимостью Gradle.

FFmpeg 6.1.6 собирается с `--disable-gpl --disable-version3 --disable-nonfree`.
Полные неизменённые исходники FFmpeg, официальные Java/JNI Media3 и рецепт сборки
попадают в `FreeScene-android-audio-sources.tar.gz` рядом с APK. Этот архив нужно
публиковать вместе с APK в Release. В FFmpeg-архиве есть `COPYING.LGPLv2.1`.
Для изменения библиотеки можно распаковать исходники, изменить их, пересобрать
и перепаковать APK, затем установить его со своим Android-ключом. Ключ автора
для этого не требуется. Проверка SHA-256 применяется к исходной загрузке;
для своих изменений нужно изменить манифест.

Архив сохраняет каталоги `tools/`, `android/app/`, `licenses/`, `docs/` и
`build/android-audio/vendor/`. Его можно пересобрать без отдельного checkout:

```sh
tar -xzf FreeScene-android-audio-sources.tar.gz
cd FreeScene-android-audio-sources
python3 tools/build_android_audio.py --sdk /path/to/android-sdk
```

Официальная документация: https://github.com/androidx/media/tree/1.11.1/libraries/decoder_ffmpeg
Исходники FFmpeg: https://ffmpeg.org/releases/ffmpeg-6.1.6.tar.xz

Отсутствие системных Dolby/DTS-кодеков подтверждено на Q12W Pro через
`MediaCodecList`, а не только по XML прошивки. Наличие модулей в APK, успешная
сборка и JVM-тесты сами по себе не подтверждают реальный звук на устройстве.
