#!/bin/bash
#
# Localepurge Zypper Plugin 0.3.5
# Author : mendres
# Release date : 09 March 2025
#
# This script is a plugin for the openSUSE zypper package manager and removes unused locale files after package installation to save disk space.
#
# Features:
# - Automatically removes locale files after package installation
# - Respects your system's locale settings
# - Configurable through simple configuration file
# - Minimal performance impact during package operations
# - Compatible with zypper and YaST

DEBUG=false
ret=0

# Get the name of the script without path for logging
SCRIPTNAME="$(basename "$0")"

# Default configuration values for locale directories and languages to keep
CONFIG_LOCALE_DIRS="/usr/share/help,/usr/share/locale,/usr/share/man,/usr/share/qt5/translations,/usr/share/qt6/translations,/usr/share/X11/locale"
CONFIG_KEEP_LOCALES="C,en"

CONFIG_FILE="/etc/localepurge-zypp.conf"

# Log a message to the system logger
log() {
    logger -p info -t "$SCRIPTNAME" --id=$$ "$@"
}

# Debug logging function (set DEBUG=true to enable)
debug() {
    $DEBUG && log "$@"
}

# Execute a command and log error output
execute() {
    debug -- "Executing: $*"

    local cmd_output=$("$@" 2>&1)
    local cmd_status=$?

    if [[ $cmd_status -ne 0 ]]; then
        ret=1
        log -- "Command failed (exit code $cmd_status): $*"
        log -- "Error output: $cmd_output"
    else
        debug -- "Command succeeded: $*"
    fi
}

# Send a response back to the zypper plugin framework
respond() {
    debug -- "<< [$1]"
    echo -ne "$1\n\n\x00"
}

# Get system locale (e.g., "en_US")
get_system_locale() {
    local system_locale=""
    
    if [[ -f "/etc/locale.conf" ]]; then
        system_locale=$(grep '^LANG=' /etc/locale.conf | cut -d'=' -f2 | sed 's/["]//g' | cut -d'.' -f1)
    else
        system_locale=$(locale | grep '^LANG=' | cut -d'=' -f2 | sed 's/["]//g' | cut -d'.' -f1)
    fi
    
    # Default to "en_US" if we couldn't determine the system locale
    if [[ -z "$system_locale" ]] || [[ "$system_locale" = "C" ]] || [[ "$system_locale" = "POSIX" ]]; then
        system_locale="en_US"
    fi
    
    printf '%s' "$system_locale"
}

# Get system language code (e.g., "en")
get_system_lang() {
    local system_locale=$(get_system_locale)
    local system_lang=$(cut -d'_' -f1 <<< "$system_locale")
    
    # Default to 'en' if we couldn't determine the system language
    if [[ -z "$system_lang" ]]; then
        system_lang="en"
    fi
    
    printf '%s' "$system_lang"
}

# Load configuration from file and process settings
load_config() {
    local config_file="$1"
    
    if [[ -f "$config_file" ]]; then
        debug -- "CONFIG_FILE: \"$config_file\""
        
        while read -r line || [[ -n "$line" ]]; do
        
            # Parse key/value pairs from config file
            if [[ $line =~ ^[[:space:]]*([^=]+)[[:space:]]*=[[:space:]]*(.*)[[:space:]]*$ ]]; then
                
                # Trim whitespace from key
                key=$(sed 's/^[[:space:]]*//;s/[[:space:]]*$//' <<< "${BASH_REMATCH[1]}")
                value="${BASH_REMATCH[2]}"

                # Remove surrounding quotes if present
                value="${value#\"}"
                value="${value%\"}"
                
                # Remove spaces
                value=$(sed 's/[[:space:]]*,[[:space:]]*/,/g' <<< "$value")
                
                # Trim leading and trailing whitespaces
                value=$(sed 's/^[[:space:]]*//;s/[[:space:]]*$//' <<< "$value")
                
                debug -- "Key: \"$key\", Value: \"$value\""
                
                case "$key" in
                    "keep_locales") CONFIG_KEEP_LOCALES="$value" ;;
                esac
            fi
        done < "$config_file"
    else
        debug -- "CONFIG_FILE: \"$config_file\" not found"
    fi

    # Process locale directories: convert to lowercase, fix X11 case, verify directory exists
    IFS=',' read -ra locale_dirs <<< "${CONFIG_LOCALE_DIRS,,}"
    locale_dirs=("${locale_dirs[@]//x11/X11}")
    locale_dirs=($(for d in "${locale_dirs[@]}"; do [[ -d "$d" ]] && printf '%s\n' "$d"; done))

    # Process locales to keep: convert to array, normalize case (C is uppercase),
    # convert country codes to uppercase (e.g., en_us -> en_US), and validate format
    IFS=',' read -ra keep_locales <<< "${CONFIG_KEEP_LOCALES,,}"
    keep_locales=($(printf '%s\n' "${keep_locales[@]}" | sed 's/\bc\b/C/g' | \
        sed 's/_\([a-z][a-z]\)/_\U\1/g' | \
        grep -E '^(C|[a-z]{2}(_[A-Z]{2})?(@[a-z0-9]+)?(\.[a-zA-Z0-9-]+)?)$'))

    # Ensure C, en, en_US and system locales are always kept
    local required_locales=("C" "en" "en_US" "$(get_system_lang)" "$(get_system_locale)")

    for locale in "${required_locales[@]}"; do
        [[ ! " ${keep_locales[*]} " =~ " ${locale} " ]] && keep_locales+=("$locale")
    done

    debug -- "system_lang: \"$(get_system_lang)\""
    debug -- "system_locale: \"$(get_system_locale)\""
    debug -- "locale_dirs: \"${locale_dirs[*]}\""
    debug -- "keep_locales: \"${keep_locales[*]}\""
}

# Purge locale directories based on specified patterns
purge_locales() {
    local locale_dir="$1"
    local exclude_pattern="$2"
    local include_pattern="$3"
    local is_single_directory="${4:-false}"
    local files_to_purge_count=0

    debug -- "locale_dir: \"$locale_dir\""
    debug -- "exclude_pattern: \"$exclude_pattern\""
    [[ -n "$include_pattern" ]] && debug -- "include_pattern: \"$include_pattern\""

    if [[ "$is_single_directory" = true ]]; then
        local search_query="find \"$locale_dir\" \\( -type f -o -type l \\)"
        [[ -n "$exclude_pattern" ]] && search_query+=" | grep -vE \"$exclude_pattern\""

        files_to_purge_count=$(eval "$search_query" | wc -l)

        debug -- "search_query: \"$search_query\""
        debug -- "Files to purge from \"$locale_dir\": $files_to_purge_count"
        
        eval "$search_query" | execute xargs -r -P4 rm -f
    else
        local search_query="find \"$locale_dir\" -mindepth 1 -maxdepth 1 -type d"
        [[ -n "$include_pattern" ]] && search_query+=" | grep -E \"$include_pattern\""
        [[ -n "$exclude_pattern" ]] && search_query+=" | grep -vE \"$exclude_pattern\""

        files_to_purge_count=$(eval "$search_query" | xargs -r -I{} find {} \( -type f -o -type l \) | wc -l)

        debug -- "search_query: \"$search_query\""
        debug -- "Files to purge from \"$locale_dir\": $files_to_purge_count"
        
        eval "$search_query" | execute xargs -r -P4 -I{} find {} \( -type f -o -type l \) -delete
    fi
}

# Process each locale directory
process_locale_dirs() {
    for locale_dir in "${locale_dirs[@]}"; do
        case $locale_dir in
            "/usr/share/help"|"/usr/share/locale")

                # exclude_pattern, e.g.: "/C($)|/en($)|/de($)"
                exclude_pattern=$(printf "/%s($)|" "${keep_locales[@]}" | sed 's/|$//')

                purge_locales "$locale_dir" "$exclude_pattern"
                ;;
            "/usr/share/man")

                # exclude_pattern, e.g.: "/C|/en|/de|/man[^/]" 
                exclude_pattern=$(printf "/%s|" "${keep_locales[@]}" | sed 's/|$//')
                exclude_pattern="$exclude_pattern|/man[^/]"

                purge_locales "$locale_dir" "$exclude_pattern"
                ;;
            "/usr/share/qt5/translations"|"/usr/share/qt6/translations")

                # exclude_pattern, e.g.: "_C\.|_en\.|_de\."
                exclude_pattern=$(printf "_%s\.|" "${keep_locales[@]}" | sed 's/|$//')

                purge_locales "$locale_dir" "$exclude_pattern" "" true
                ;;
            "/usr/share/X11/locale")

                # include_pattern, e.g.: "/..([_.]|$)"
                include_pattern="/..([_.]|$)"

                # exclude_pattern, e.g.: "/C([_.]|$)|/en([_.]|$)|/de([_.]|$)"
                exclude_pattern=$(printf "|/%s([_.]|$)" "${keep_locales[@]}" | sed 's/^|//')

                purge_locales "$locale_dir" "$exclude_pattern" "$include_pattern"
                ;;
            *)
                ;;
        esac
    done
}

# Parsing libzypp commands, waiting for PLUGINBEGIN and COMMITEND
while IFS= read -r -d $'\0' FRAME; do
    debug -- ">> $FRAME"

    read COMMAND <<<$FRAME

    debug -- "COMMAND=[$COMMAND]"
    case "$COMMAND" in
    PLUGINBEGIN)
        load_config "$CONFIG_FILE"

        respond "ACK"
        continue
        ;;
    COMMITEND)
        process_locale_dirs

        if [[ $ret -ne 0 ]]; then
            respond "ERROR"
        else
            respond "ACK"
        fi
        ;;
    _DISCONNECT)
        respond "ACK"
        break
        ;;
    *)
        respond "_ENOMETHOD"
        continue
        ;;
    esac
done

debug -- "Terminating with exit code $ret"
exit $ret
