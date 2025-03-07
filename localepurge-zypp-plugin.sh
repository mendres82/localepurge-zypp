#!/bin/bash
#
# This plugin purges localefiles after an installation or update.

DEBUG="false"

SCRIPTNAME="$(basename "$0")"

# Default configuration values for locale directories and languages to keep
CONFIG_LOCALE_DIRS="/usr/share/help,/usr/share/locale,/usr/share/man,/usr/share/qt5/translations,/usr/share/X11/locale"
CONFIG_KEEP_LOCALES="C,en"

CONFIG_FILE="/etc/localepurge-zypp.conf"

log() {
    logger -p info -t $SCRIPTNAME --id=$$ "$@"
}

debug() {
    $DEBUG && log "$@"
}

respond() {
    debug "<< [$1]"
    echo -ne "$1\n\n\x00"
}

# Helper function to split comma-separated strings into arrays
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

# Get full system locale (e.g., "en_US.UTF-8")
get_system_locale() {
    local system_locale=$(locale | grep LANG | cut -d'=' -f2 | head -n1 | cut -d'.' -f1)
    
    # Default to "en_US.UTF-8" if we couldn't determine the system locale
    if [ -z "$system_locale" ]; then
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
        while read -r line || [ -n "$line" ]; do
        
            # Parse key-value pairs from config file
            if [[ $line =~ ^[[:space:]]*([^=]+)[[:space:]]*=[[:space:]]*(.*)[[:space:]]*$ ]]; then
                key="${BASH_REMATCH[1]}"
                value="${BASH_REMATCH[2]}"

                # Remove surrounding quotes if present
                value="${value#\"}"
                value="${value%\"}"
                
                debug "Key: $key, Value: $value"
                
                case "$key" in
                    "keep_locales") CONFIG_KEEP_LOCALES="$value" ;;
                esac
            fi
        done < "$config_file"
    else
        debug "CONFIG_FILE: $config_file not found"
    fi

    # Process locale directories: convert to lowercase, fix X11 case, verify directory exists
    readarray -t locale_dirs < <(split "${CONFIG_LOCALE_DIRS,,}" | sed 's/x11/X11/g' | while read dir; do [ -d "$dir" ] && echo "$dir"; done)

    # Process keep_locales: convert to lowercase except 'C', validate format (2 letters or 'C')
    readarray -t keep_locales < <(split "${CONFIG_KEEP_LOCALES}" | sed 's/\([^,]*\)/\L\1/g; s/\bc\b/C/g' | while read locale; do
        if [[ "$locale" =~ ^[[:alpha:]]{2}$ ]] || [ "$locale" = "C" ]; then
            echo "$locale"
        fi
    done)

    # Ensure C, en, en_US and system locales are always kept
    if [[ ! " ${keep_locales[@]} " =~ " C " ]]; then
        keep_locales+=("C")
    fi

    if [[ ! " ${keep_locales[@]} " =~ " en " ]]; then
        keep_locales+=("en")
    fi

    if [[ ! " ${keep_locales[@]} " =~ " en_US " ]]; then
        keep_locales+=("en_US")
    fi

    local system_lang=$(get_system_lang)
    if [[ ! " ${keep_locales[@]} " =~ " $system_lang " ]]; then
        keep_locales+=("$system_lang")
    fi

    local system_locale=$(get_system_locale)
    if [[ ! " ${keep_locales[@]} " =~ " $system_locale " ]]; then
        keep_locales+=("$system_locale")
    fi

    debug "system_lang: $system_lang"
    debug "system_locale: $system_locale"
    debug "locale_dirs: ${locale_dirs[@]}"
    debug "keep_locales: ${keep_locales[@]}"
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

        # Find and purge individual files
        local files_to_purge=$(find "$locale_dir" \( -type f -o -type l \) | grep -vE "$search_pattern")

        for file_to_purge in $files_to_purge; do
            rm -f "$file_to_purge"
        done
    else
    
        # Find and purge directories
        local dirs_query="find \"$locale_dir\" -mindepth 1 -maxdepth 1 -type d"
        [[ -n "$include_pattern" ]] && dirs_query+=" | grep -E \"$include_pattern\""
        [[ -n "$exclude_pattern" ]] && dirs_query+=" | grep -vE \"$exclude_pattern\""
        [[ -z "$include_pattern" ]] && dirs_query+=" | grep -vE \"$search_pattern\""
        
        local dirs_to_purge=$(eval "$dirs_query")
        
        for dir_to_purge in $dirs_to_purge; do
            find "$dir_to_purge" \( -type f -o -type l \) -exec rm -f {} +
        done
    fi
}

ret=0

# The frames are terminated with NUL.  Use that as the delimeter and get
# the whole frame in one go.
while IFS= read -r -d $'\0' FRAME; do
    echo ">>" $FRAME | debug

    # We only want the command, which is the first word
    read COMMAND <<<$FRAME

    # libzypp will only close the plugin on errors, which may also be logged.
    # It will also log if the plugin exits unexpectedly.  We don't want
    # to create a noisy log when using another file system, so we just
    # wait until COMMITEND to do anything.  We also need to ACK _DISCONNECT
    # or libzypp will kill the script, which means we can't clean up.
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
