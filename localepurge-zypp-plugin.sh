#!/bin/bash

split() {
    local IFS=","
    read -ra RESULT <<< "$1"
    printf '%s\n' "${RESULT[@]}"
}

CONFIG_LOCALE_DIRS="/usr/share/help,/usr/share/locale,/usr/share/man,/usr/share/qt5/translations,/usr/share/X11/locale"
CONFIG_KEEP_LOCALES="C,en,de"

readarray -t locale_dirs < <(split "${CONFIG_LOCALE_DIRS,,}")
readarray -t keep_locales < <(split "${CONFIG_KEEP_LOCALES,,}")

if [[ ! " ${keep_locales[@]} " =~ " C " ]]; then
    keep_locales+=("C")
fi

for locale_dir in "${locale_dirs[@]}"; do
    case $locale_dir in
        "/usr/share/help")
            searchpattern=$(printf "/%s|" "${keep_locales[@]}" | sed 's/|$//')
            dirs_to_purge=$(find $locale_dir -mindepth 1 -maxdepth 1 -type d | grep -vE "$searchpattern")
            # for dir_to_purge in $dirs_to_purge; do
            #     find $dir_to_purge -type f -exec rm -f {} +
            # done
            ;;
        "/usr/share/locale")
            searchpattern=$(printf "/%s|" "${keep_locales[@]}" | sed 's/|$//')
            dirs_to_purge=$(find $locale_dir -mindepth 1 -maxdepth 1 -type d | grep -vE "$searchpattern")
            # for dir_to_purge in $dirs_to_purge; do
            #     find $dir_to_purge -type f -exec rm -f {} +
            # done
            ;;
        "/usr/share/man")
            searchpattern=$(printf "/%s|" "${keep_locales[@]}" | sed 's/|$//')
            searchpattern="$searchpattern|/man[^/]"
            dirs_to_purge=$(find $locale_dir -mindepth 1 -maxdepth 1 -type d | grep -vE "$searchpattern")
            # for dir_to_purge in $dirs_to_purge; do
            #     find $dir_to_purge -type f -exec rm -f {} +
            # done
            ;;
        "/usr/share/qt5/translations")
            searchpattern=$(printf "_%s\.|" "${keep_locales[@]}" | sed 's/|$//')
            # find $locale_dir -type f | grep -vE "$searchpattern" | xargs rm -f
            ;;
        "/usr/share/X11/locale")
            ;;
        *)
            ;;
    esac
done
