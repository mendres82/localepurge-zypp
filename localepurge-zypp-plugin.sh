#!/bin/bash

# Default configuration values for locale directories and languages to keep
CONFIG_LOCALE_DIRS="/usr/share/help,/usr/share/locale,/usr/share/man,/usr/share/qt5/translations,/usr/share/X11/locale"
CONFIG_KEEP_LOCALES="C,en"

CONFIG_FILE="./localepurge-zypp.conf"

# Check if script is running with root privileges
check_runas_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}Error: This script must be run as root!${NC}"
        echo
        exit 1
    fi
}

# Helper function to split comma-separated strings into arrays
split() {
    local IFS=","
    read -ra RESULT <<< "$1"
    printf '%s\n' "${RESULT[@]}"
}

check_runas_root

# Load configuration from file if it exists
if [ -f "$CONFIG_FILE" ]; then
    echo "CONFIG_FILE: $CONFIG_FILE"
    while read -r line || [ -n "$line" ]; do

        # Parse key-value pairs from config file
        if [[ $line =~ ^[[:space:]]*([^=]+)[[:space:]]*=[[:space:]]*(.*)[[:space:]]*$ ]]; then
            key="${BASH_REMATCH[1]}"
            value="${BASH_REMATCH[2]}"

            # Remove surrounding quotes if present
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

# Process locale directories: convert to lowercase, fix X11 case, verify directory exists
readarray -t locale_dirs < <(split "${CONFIG_LOCALE_DIRS,,}" | sed 's/x11/X11/g' | while read dir; do [ -d "$dir" ] && echo "$dir"; done)

# Process keep_locales: convert to lowercase except 'C', validate format (2 letters or 'C')
readarray -t keep_locales < <(split "${CONFIG_KEEP_LOCALES}" | sed 's/\([^,]*\)/\L\1/g; s/\bc\b/C/g' | while read locale; do
    if [[ "$locale" =~ ^[[:alpha:]]{2}$ ]] || [ "$locale" = "C" ]; then
        echo "$locale"
    fi
done)

# Ensure C and en locales are always kept
if [[ ! " ${keep_locales[@]} " =~ " C " ]]; then
    keep_locales+=("C")
fi

if [[ ! " ${keep_locales[@]} " =~ " en " ]]; then
    keep_locales+=("en")
fi

echo "locale_dirs: ${locale_dirs[@]}"
echo "keep_locales: ${keep_locales[@]}"

# Process each locale directory
for locale_dir in "${locale_dirs[@]}"; do
    case $locale_dir in
        "/usr/share/help"|"/usr/share/locale")
            echo "locale_dir: $locale_dir"

            # Create pattern to match directories to keep
            # searchpattern, e.g.: "/C|/en|/de"
            searchpattern=$(printf "/%s|" "${keep_locales[@]}" | sed 's/|$//')
            echo "searchpattern: $searchpattern"

            # Find directories to purge (those not matching keep pattern)
            dirs_to_purge=$(find $locale_dir -mindepth 1 -maxdepth 1 -type d | grep -vE "$searchpattern")
            echo "dirs_to_purge: $dirs_to_purge"

            # Remove files and symlinks in purge directories
            for dir_to_purge in $dirs_to_purge; do
                find $dir_to_purge \( -type f -o -type l \) -exec rm -f {} +
            done
            ;;
        "/usr/share/man")
            echo "locale_dir: $locale_dir"

            # Include man pages directory pattern
            # searchpattern, e.g.: "/C|/en|/de|/man[^/]" 
            searchpattern=$(printf "/%s|" "${keep_locales[@]}" | sed 's/|$//')
            searchpattern="$searchpattern|/man[^/]"
            echo "searchpattern: $searchpattern"

            # Find directories to purge (those not matching keep pattern)
            dirs_to_purge=$(find $locale_dir -mindepth 1 -maxdepth 1 -type d | grep -vE "$searchpattern")
            echo "dirs_to_purge: $dirs_to_purge"

            # Remove files and symlinks in purge directories
            for dir_to_purge in $dirs_to_purge; do
                find $dir_to_purge \( -type f -o -type l \) -exec rm -f {} +
            done
            ;;
        "/usr/share/qt5/translations")
            echo "locale_dir: $locale_dir"

            # Match Qt translation files by locale suffix
            # searchpattern, e.g.: "_C\.|_en\.|_de\.|"
            searchpattern=$(printf "_%s\.|/_%s\.|/_%s\.|" "${keep_locales[@]}" | sed 's/|$//')
            echo "searchpattern: $searchpattern"

            # Find files to purge (those not matching keep pattern)
            files_to_purge=$(find $locale_dir \( -type f -o -type l \) | grep -vE "$searchpattern")
            echo "files_to_purge: $files_to_purge"

            # Remove files and symlinks in purge directories
            for file_to_purge in $files_to_purge; do
                rm -f "$file_to_purge"
            done
            ;;
        "/usr/share/X11/locale")
            echo "locale_dir: $locale_dir"

            # Special handling for X11 locale directories
            # include_pattern, e.g.: "/..([_.]|$)"
            include_pattern="/..([_.]|$)"
            echo "include_pattern: $include_pattern"

            # exclude_pattern, e.g.: "/C([_.]|$)|/en([_.]|$)|/de([_.]|$)"
            exclude_pattern=$(printf "|/%s([_.]|$)" "${keep_locales[@]}" | sed 's/^|//')
            echo "exclude_pattern: $exclude_pattern"

            # Find directories to purge (those not matching keep pattern)
            dirs_to_purge=$(find $locale_dir -mindepth 1 -maxdepth 1 -type d | grep -E "$include_pattern" | grep -vE "$exclude_pattern")
            echo "dirs_to_purge: $dirs_to_purge"

            # Remove files and symlinks in purge directories
            for dir_to_purge in $dirs_to_purge; do
                find $dir_to_purge \( -type f -o -type l \) -exec rm -f {} +
            done
            ;;
        *)
            ;;
    esac
done
