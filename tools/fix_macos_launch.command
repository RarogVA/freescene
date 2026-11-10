#!/bin/zsh

if [[ ! -d /Applications/FreeScene.app ]]; then
    printf '%s\n' 'Сначала перетащите FreeScene.app в папку Applications.'
    exit 1
fi

if /usr/bin/xattr -r -c /Applications/FreeScene.app; then
    printf '%s\n' 'Готово. Теперь откройте FreeScene из папки Applications.'
else
    printf '%s\n' 'Не удалось исправить запуск. Проверьте права доступа к /Applications/FreeScene.app.' >&2
    exit 1
fi
