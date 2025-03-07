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

# Load configuration from file and process settings
load_config() {
    local config_file="$1"
    
    if [ -f "$config_file" ]; then
        echo "CONFIG_FILE: $config_file"
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
        done < "$config_file"
    else
        echo "CONFIG_FILE: $config_file not found"
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
}

# Purge locale directories based on specified patterns
purge_locales() {
    local locale_dir="$1"
    local search_pattern="$2"
    local include_pattern="$3"
    local exclude_pattern="$4"
    local is_file_based="${5:-false}"

    echo "locale_dir: $locale_dir"
    echo "searchpattern: $search_pattern"
    [[ -n "$include_pattern" ]] && echo "include_pattern: $include_pattern"
    [[ -n "$exclude_pattern" ]] && echo "exclude_pattern: $exclude_pattern"

    if [[ "$is_file_based" == "true" ]]; then

        # Find and purge individual files
        local files_to_purge=$(find "$locale_dir" \( -type f -o -type l \) | grep -vE "$search_pattern")
        echo "files_to_purge: $files_to_purge"

        # for file_to_purge in $files_to_purge; do
        #     rm -f "$file_to_purge"
        # done
    else
    
        # Find and purge directories
        local dirs_query="find \"$locale_dir\" -mindepth 1 -maxdepth 1 -type d"
        [[ -n "$include_pattern" ]] && dirs_query+=" | grep -E \"$include_pattern\""
        [[ -n "$exclude_pattern" ]] && dirs_query+=" | grep -vE \"$exclude_pattern\""
        [[ -z "$include_pattern" ]] && dirs_query+=" | grep -vE \"$search_pattern\""
        
        local dirs_to_purge=$(eval "$dirs_query")
        echo "dirs_to_purge: $dirs_to_purge"
        
        # for dir_to_purge in $dirs_to_purge; do
        #     find "$dir_to_purge" \( -type f -o -type l \) -exec rm -f {} +
        # done
    fi
}

check_runas_root
load_config "$CONFIG_FILE"

# Process each locale directory
for locale_dir in "${locale_dirs[@]}"; do
    case $locale_dir in
        "/usr/share/help"|"/usr/share/locale")

            # searchpattern, e.g.: "/C|/en|/de"
            searchpattern=$(printf "/%s|" "${keep_locales[@]}" | sed 's/|$//')

            purge_locales "$locale_dir" "$searchpattern"
            ;;
        "/usr/share/man")

            # searchpattern, e.g.: "/C|/en|/de|/man[^/]" 
            searchpattern=$(printf "/%s|" "${keep_locales[@]}" | sed 's/|$//')
            searchpattern="$searchpattern|/man[^/]"

            purge_locales "$locale_dir" "$searchpattern"
            ;;
        "/usr/share/qt5/translations")

            # searchpattern, e.g.: "_C\.|_en\.|_de\."
            searchpattern=$(printf "_%s\.|_%s\.|_%s\.|" "${keep_locales[@]}" | sed 's/|$//')

            purge_locales "$locale_dir" "$searchpattern" "" "" "true"
            ;;
        "/usr/share/X11/locale")

            # include_pattern, e.g.: "/..([_.]|$)"
            include_pattern="/..([_.]|$)"

            # exclude_pattern, e.g.: "/C([_.]|$)|/en([_.]|$)|/de([_.]|$)"
            exclude_pattern=$(printf "|/%s([_.]|$)" "${keep_locales[@]}" | sed 's/^|//')

            purge_locales "$locale_dir" "" "$include_pattern" "$exclude_pattern"
            ;;
        *)
            ;;
    esac
done
