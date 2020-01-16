#!/bin/sh

# Requires: cat, rm, mkdir, wget, cmp

# We are started by "d-i preseed/run string <script>" from preseed file.
# That <script> might be downloaded from relative to preseed file
# URL given with preseed/url= unless <script> is absolute path.
#
# Since we running in same environment as debian-installer we can
# access debconf-get and debconf-set utilities to get/set debconf
# database values.

# Target distro
SIMPLE_CDD_DISTRO='debian'

# Make sure we have stable name as we might be executed from pipe
prog_name='init.sh'

# Make sure logged names are unique
log_name="$SIMPLE_CDD_DISTRO/$prog_name"

# Find interpreted script or try ./$prog_name as last resort (Linux specific)
[ ! -e "$0" -o "$0" -ef "/proc/$$/exe" ] && this="./$prog_name" || this="$0"

# Usage: get_url_base <url> [<run>]
get_url_base()
{
    local url="$1" # preseed file URL
    local run="$2"

    # No or invalid URL given: bailout
    [ -n "$url" -a -z "${url##*/*}" ] || return 0

    # Get rid of file://
    url="${url#file://}"
    if [ -n "${url##*://*}" ]; then
        if [ -n "${url##/*}" ]; then
            # Last resort try $this script directory
            url="${this%/*}/${url}"
        fi
    fi
    # Base URL ended with '/' (could be just '/' or even 'http://')
    url="${url%/*}/"

    if [ -z "$run" ]; then
        # Last resort try fixed $prog_name
        url="$url$prog_name"
    else
        local t="$run"
        if [ -z "${t##*://*}" ]; then
            # It is network or file URL? (e.g. http://... or file://...)
            t="${t#file://}"
            [ "$run" != "$t" ] && run="$t" || run=''
        fi
        if [ -n "${run##/*}" ]; then
            # Relative filesystem path
            url="$url$t"
        else
            # Absolute filesystem path
            url="$t"
        fi
    fi

    # Skip tests if this running script file cannot be accessed
    if [ -f "$this" ]; then
        # wget(1) does not support file:// schema compared to curl(1)
        if [ -z "${url##*://*}" ]; then
            wget -q -O /dev/stdout "$url"
        else
            cat "$url" 2>/dev/null
        fi | \
        cmp -s "$this" /dev/stdin || return
    fi

    # Make sure we end with '/' to catch cases like "http://"
    url="${url%/*}"
    [ -z "$url" -o -n "${url#*:/}" ] || url="$url/"

    echo "$url"
}

# Usage: get_url_method <url>
get_url_method()
{
    local func="${FUNCNAME:-get_url_method}"

    local url="${1:?missing 1st arg to ${func}() <url>}"

    # Determine method. Since wget(1) does not support file://
    # schema use empty ('') method for local filesystem.
    local method="${url%%://*}"
    [ "$method" != "$url" -a "$method" != 'file' ] || method=''

    echo "$method"
}

################################################################################

## Install default exit handler

exit_handler()
{
    local rc=$?

    # Do not interrupt exit hander
    set +e

    if [ $rc -ne 0 ]; then
        echo >&2 "$log_name: exiting due to error, rc == $rc"
    fi

    return $rc
}
trap 'exit_handler' EXIT

## Exit as long as command pipeline fails

set -e

## Find base URL

# No default URL
url=

# preseed/run
run="$(debconf-get 'preseed/run')"

# preseed/file
url="${url:-$(get_url_base "$(debconf-get 'preseed/file')" "$run")}"
# preseed/url
url="${url:-$(get_url_base "$(debconf-get 'preseed/url')" "$run")}"

if [ -z "$url" ]; then
    echo >&2 "$log_name: unable to locate base URL for running script"
    exit 1
fi

## Setup global environment for common/init.sh

SIMPLE_CDD_URL_METHOD="$(get_url_method "$url")"
SIMPLE_CDD_URL_BASE="$url"

SIMPLE_CDD_DIR='/cdrom/simple-cdd'
#SIMPLE_CDD_DISTRO=<set earlier>

## Fetch or copy common/init.sh

f='common/init.sh'
url="$SIMPLE_CDD_URL_BASE/$f"
f="$SIMPLE_CDD_DIR/$f"

if [ ! "$url" -ef "$f" ]; then
    # Make sure directory tree exists
    mkdir -p "${f%/*}" ||:

    rc=0
    if [ -n "$SIMPLE_CDD_URL_METHOD" ]; then
        wget -q -O "$f" "$url" || rc=$?
    else
        { cat "$url" >"$f"; } 2>/dev/null || rc=$?
    fi

    if [ $rc -ne 0 ]; then
        echo >&2 "$log_name: fetching \"$url\" to \"$f\" failed"
        exit $rc
    fi
fi

## Continue in common/init.sh

. "$f"

exit 0
