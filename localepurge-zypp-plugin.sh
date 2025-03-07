#!/bin/bash

CONFIG_LOCALE_DIRS="/usr/share/help,/usr/share/locale,/usr/share/man,/usr/share/qt5/translations,/usr/share/X11/locale"
CONFIG_KEEP_LOCALES="C,en"

CONFIG_FILE="./localepurge-zypp.conf"

if [ -f "$CONFIG_FILE" ]; then
    echo "CONFIG_FILE: $CONFIG_FILE"
    while read -r line || [ -n "$line" ]; do
        if [[ $line =~ ^[[:space:]]*([^=]+)[[:space:]]*=[[:space:]]*(.*)[[:space:]]*$ ]]; then
            key="${BASH_REMATCH[1]}"
            value="${BASH_REMATCH[2]}"
            value="${value#\"}"
            value="${value%\"}"
            
            echo "Key: $key, Value: $value"
            
            case "$key" in
                "locale_dirs") CONFIG_LOCALE_DIRS="$value" ;;
                "keep_locales") CONFIG_KEEP_LOCALES="$value" ;;
            esac
        fi
    done < "$CONFIG_FILE"
else
    echo "CONFIG_FILE: $CONFIG_FILE not found"
fi

split() {
    local IFS=","
    read -ra RESULT <<< "$1"
    printf '%s\n' "${RESULT[@]}"
}

readarray -t locale_dirs < <(split "${CONFIG_LOCALE_DIRS,,}" | sed 's/x11/X11/g' | while read dir; do [ -d "$dir" ] && echo "$dir"; done)
readarray -t keep_locales < <(split "${CONFIG_KEEP_LOCALES}" | sed 's/\([^,]*\)/\L\1/g; s/\bc\b/C/g' | while read locale; do
    if [[ "$locale" =~ ^[[:alpha:]]{2}$ ]] || [ "$locale" = "C" ]; then
        echo "$locale"
    fi
done)

if [[ ! " ${keep_locales[@]} " =~ " C " ]]; then
    keep_locales+=("C")
fi

if [[ ! " ${keep_locales[@]} " =~ " en " ]]; then
    keep_locales+=("en")
fi

echo "locale_dirs: ${locale_dirs[@]}"
echo "keep_locales: ${keep_locales[@]}"

for locale_dir in "${locale_dirs[@]}"; do
    case $locale_dir in
        "/usr/share/help")
            echo "locale_dir: $locale_dir"
            searchpattern=$(printf "/%s|" "${keep_locales[@]}" | sed 's/|$//')
            echo "searchpattern: $searchpattern"
            dirs_to_purge=$(find $locale_dir -mindepth 1 -maxdepth 1 -type d | grep -vE "$searchpattern")
            echo "dirs_to_purge: $dirs_to_purge"
            for dir_to_purge in $dirs_to_purge; do
                find $dir_to_purge \( -type f -o -type l \) -exec rm -f {} +
            done
            ;;
        "/usr/share/locale")
            echo "locale_dir: $locale_dir"
            searchpattern=$(printf "/%s|" "${keep_locales[@]}" | sed 's/|$//')
            echo "searchpattern: $searchpattern"
            dirs_to_purge=$(find $locale_dir -mindepth 1 -maxdepth 1 -type d | grep -vE "$searchpattern")
            echo "dirs_to_purge: $dirs_to_purge"
            for dir_to_purge in $dirs_to_purge; do
                find $dir_to_purge \( -type f -o -type l \) -exec rm -f {} +
            done
            ;;
        "/usr/share/man")
            echo "locale_dir: $locale_dir"
            searchpattern=$(printf "/%s|" "${keep_locales[@]}" | sed 's/|$//')
            searchpattern="$searchpattern|/man[^/]"
            echo "searchpattern: $searchpattern"
            dirs_to_purge=$(find $locale_dir -mindepth 1 -maxdepth 1 -type d | grep -vE "$searchpattern")
            echo "dirs_to_purge: $dirs_to_purge"
            for dir_to_purge in $dirs_to_purge; do
                find $dir_to_purge \( -type f -o -type l \) -exec rm -f {} +
            done
            ;;
        "/usr/share/qt5/translations")
            echo "locale_dir: $locale_dir"
            searchpattern=$(printf "_%s\.|" "${keep_locales[@]}" | sed 's/|$//')
            echo "searchpattern: $searchpattern"
            files_to_purge=$(find $locale_dir \( -type f -o -type l \) | grep -vE "$searchpattern")
            echo "files_to_purge: $files_to_purge"
            for file_to_purge in $files_to_purge; do
                rm -f "$file_to_purge"
            done
            ;;
        "/usr/share/X11/locale")
            echo "locale_dir: $locale_dir"
            include_pattern="/..([_.]|$)"
            exclude_pattern=$(printf "|/%s([_.]|$)" "${keep_locales[@]}" | sed 's/^|//')
            echo "include_pattern: $include_pattern"
            echo "exclude_pattern: $exclude_pattern"
            dirs_to_purge=$(find $locale_dir -mindepth 1 -maxdepth 1 -type d | grep -E "$include_pattern" | grep -vE "$exclude_pattern")
            echo "dirs_to_purge: $dirs_to_purge"
            for dir_to_purge in $dirs_to_purge; do
                find $dir_to_purge \( -type f -o -type l \) -exec rm -f {} +
            done
            ;;
        *)
            ;;
    esac
done
