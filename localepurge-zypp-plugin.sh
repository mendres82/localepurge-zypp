#!/bin/bash
#
# This plugin purges localefiles after an installation or update.

DEBUG="false"

# Get the name of the script without path for logger
SCRIPTNAME="$(basename "$0")"

# Default configuration values for locale directories and languages to keep
CONFIG_LOCALE_DIRS="/usr/share/help,/usr/share/locale,/usr/share/man,/usr/share/qt5/translations,/usr/share/X11/locale"
CONFIG_KEEP_LOCALES="C,en"

CONFIG_FILE="/etc/localepurge-zypp.conf"

# Log a message to the system logger (syslog)
log() {
    logger -p info -t $SCRIPTNAME --id=$$ "$@"
}

# Debug logging function that only logs if DEBUG is true
debug() {
    $DEBUG && log "$@"
}

# Send a response back to the zypper plugin framework
respond() {
    debug "<< [$1]"
    echo -ne "$1\n\n\x00"
}

# Split comma-separated strings into arrays
split() {
    local IFS=","
    read -ra RESULT <<< "$1"
    printf '%s\n' "${RESULT[@]}"
}

# Check if script is running with root privileges
check_runas_root() {
    if [ "$EUID" -ne 0 ]; then
        exit 1
    fi
}

# Get system locale (e.g., "en_US")
get_system_locale() {
    
    # Check LC_ALL first, then LC_CTYPE, then LANG
    local system_locale=$(locale | grep -E '^(LC_ALL|LC_CTYPE|LANG)=' | head -n1 | cut -d'=' -f2 | sed 's/["]//g' | cut -d'.' -f1)
    
    # Default to "en_US" if we couldn't determine the system locale
    if [ -z "$system_locale" ] || [ "$system_locale" = "C" ] || [ "$system_locale" = "POSIX" ]; then
        system_locale="en_US"
    fi
    
    echo "$system_locale"
}

# Get system language code (e.g., "en")
get_system_lang() {
    local system_locale=$(get_system_locale)
    local system_lang=$(echo "$system_locale" | cut -d'_' -f1)
    
    # Default to 'en' if we couldn't determine the system language
    if [ -z "$system_lang" ]; then
        system_lang="en"
    fi
    
    echo "$system_lang"
}

# Load configuration from file and process settings
load_config() {
    local config_file="$1"
    
    if [ -f "$config_file" ]; then
        debug "CONFIG_FILE: $config_file"
        mapfile -t config_lines < "$config_file"
        for line in "${config_lines[@]}"; do
            if [[ $line =~ ^[[:space:]]*([^=]+)[[:space:]]*=[[:space:]]*(.*)[[:space:]]*$ ]]; then
                key="${BASH_REMATCH[1]}"
                value="${BASH_REMATCH[2]//\"/}"  # More efficient quote removal
                
                debug "Key: $key, Value: $value"
                case "$key" in
                    "keep_locales") CONFIG_KEEP_LOCALES="$value" ;;
                esac
            fi
        done
    else
        debug "CONFIG_FILE: $config_file not found"
    fi

    # Process locale directories: convert to lowercase, fix X11 case, verify directory exists
    IFS=',' read -ra locale_dirs <<< "${CONFIG_LOCALE_DIRS,,}"
    locale_dirs=("${locale_dirs[@]//x11/X11}")
    locale_dirs=($(for d in "${locale_dirs[@]}"; do [ -d "$d" ] && echo "$d"; done))

    IFS=',' read -ra keep_locales <<< "${CONFIG_KEEP_LOCALES,,}"
    keep_locales=($(printf '%s\n' "${keep_locales[@]}" | sed 's/\bc\b/C/g' | grep -E '^([[:alpha:]]{2}|C)$'))

    # Ensure C, en, en_US and system locales are always kept
    local required_locales=("C" "en" "en_US" "$(get_system_lang)" "$(get_system_locale)")
    for locale in "${required_locales[@]}"; do
        [[ ! " ${keep_locales[*]} " =~ " ${locale} " ]] && keep_locales+=("$locale")
    done

    debug "system_lang: $(get_system_lang)"
    debug "system_locale: $(get_system_locale)"
    debug "locale_dirs: ${locale_dirs[*]}"
    debug "keep_locales: ${keep_locales[*]}"
}

# Purge locale directories based on specified patterns
purge_locales() {
    local locale_dir="$1"
    local search_pattern="$2"
    local include_pattern="$3"
    local exclude_pattern="$4"
    local is_file_based="${5:-false}"

    debug "locale_dir: $locale_dir"
    debug "searchpattern: $search_pattern"
    [[ -n "$include_pattern" ]] && debug "include_pattern: $include_pattern"
    [[ -n "$exclude_pattern" ]] && debug "exclude_pattern: $exclude_pattern"

    if [[ "$is_file_based" == "true" ]]; then

        # Find and purge files
        find "$locale_dir" \( -type f -o -type l \) -not -regex ".*${search_pattern}.*" -delete
    else
        local dirs_query="find \"$locale_dir\" -mindepth 1 -maxdepth 1 -type d"
        [[ -n "$include_pattern" ]] && dirs_query+=" | grep -E \"$include_pattern\""
        [[ -n "$exclude_pattern" ]] && dirs_query+=" | grep -vE \"$exclude_pattern\""
        [[ -z "$include_pattern" ]] && dirs_query+=" | grep -vE \"$search_pattern\""
        
        eval "$dirs_query" | xargs -r -P4 -I{} find {} \( -type f -o -type l \) -delete
    fi
}

ret=0

# Parsing libzypp hooks and waiting for COMMITEND
while IFS= read -r -d $'\0' FRAME; do
    echo ">>" $FRAME | debug

    read COMMAND <<<$FRAME

    debug "COMMAND=[$COMMAND]"
    case "$COMMAND" in
    COMMITEND)
        respond "ACK"

        check_runas_root
        load_config "$CONFIG_FILE"

        # Process each locale directory
        for locale_dir in "${locale_dirs[@]}"; do
            case $locale_dir in
                "/usr/share/help"|"/usr/share/locale")

                    # searchpattern, e.g.: "/C($)|/en($)|/de($)"
                    searchpattern=$(printf "/%s($)|" "${keep_locales[@]}" | sed 's/|$//')

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

debug "Terminating with exit code $ret"
exit $ret
