#!/bin/sh

# Requires: tr, sed, sort

[ -z "${__bootstrap_sh__}" ] || return 0
__bootstrap_sh__=1

if [ ! -e "$0" -o "$0" -ef "/proc/$$/exe" ]; then
    # Executed script is
    #  a) read from stdin through pipe
    #  b) specified via -c option
    #  d) sourced
    this='bootstrap.sh'
    this_dir='./'
else
    # Executed script exists and it's inode differs
    # from process exe symlink (Linux specific)
    this="$0"
    this_dir="${this%/*}/"
fi
this_dir="$(cd "$this_dir" && echo "$PWD")"

# Set program name unless already set
[ -n "$prog_name" ] || prog_name="${this##*/}"

# Log our errors with specific prefix
save_log_name="$log_name"
log_name="common/$prog_name:bootstrap.sh"

## Helpers providing additional functionality or compatibility

# Usage: true/false
true()  {   :; }
false() { ! :; }

# Usage: tolower/toupper <str>...
tolower() { { IFS='' && echo "$*"; } | tr '[:upper:]' '[:lower:]'; }
toupper() { { IFS='' && echo "$*"; } | tr '[:lower:]' '[:upper:]'; }

# Usage: min/max <i1> <i2>
min() { [ "$1" -le "$2" ] && echo "$1" || echo "$2"; }
max() { [ "$1" -ge "$2" ] && echo "$1" || echo "$2"; }

# Usage: subst <str> <substr>
subst()
{
    local func="${FUNCNAME:-subst}"

    local str="${1:?missing 1st arg to ${func}() <str>}"
    local substr="${2:?missing 2d arg to ${func}() <substr>}"

    local t r=''

    while :; do
        t="${str%%$substr*}"
        r="$r$t"
        [ "$t" != "$str" ] || break
        str="${str##$t$substr}"
    done

    echo "$r"
}

# Usage: unique [<sep>] <val1>...
unique()
{
    local func="${FUNCNAME:-unique}"

    local sep="${1:-|}"
    shift
    local r

    r="$sep"
    while [ $# -gt 0 ]; do
        [ -z "${r##*$sep$1$sep*}" ] ||
            r="$r$1$sep"
        shift
    done

    echo "$r"
}

# Usage: get_cmdline_var <var> [<default>] [<sep>] [<file>]
get_cmdline_var()
{
    local func="${FUNCNAME:-get_cmdline_var}"

    local var="${1:?missing 1st arg to ${func}() <var>}"
    local file="$4"
    local sep="$(expr substr "$3" 1 1)"
    local val="${2:+$2$sep}"

    set -- $(cat ${file:-/proc/cmdline})

    while [ $# -gt 0 ]; do
        case "$1" in
            $var=*) [ -n "$sep" ] && val="$val${1#*=}$sep" || val="${1#*=}" ;;
        esac
        shift
    done

    if [ -n "$sep" ]; then
        val="$(unique "$sep" $(IFS="$sep" && echo ${val%$sep}))"
        val="${val#,}"
        val="${val%,}"
    fi

    echo "$val"
}

# Usage: split_url <url>
split_url()
{
    local func="${FUNCNAME:-split_url}"

    local url="${1:?missing 1st arg to ${func}() <url>}"

    local method host dir

    if [ -z "${url##*://*}" ]; then
        method="${url%%://*}"

        dir="${url#*://}"
        host="${dir%%/*}"

        dir="${dir#$host}"
    else
        method='file'

        dir="$url"

        host=''
    fi

    dir="/$(echo "$dir" | sed -e 's/\(^\/\+\|\/\+$\)//g')"

    echo "method='$method' host='$host' dir='$dir'"
}

# Usage: read_profiles_conf <cb>
read_profiles_conf()
{
    if [ -n "${__in_installer_env__+x}" ]; then
        # Protect against of "$@" modification by "set" by foregin code
        read_profiles_conf__include() { [ ! -r "$1" ] || . "$1"; }

        cd "$SIMPLE_CDD_DIR"

        local p
        for p in $SIMPLE_CDD_PROFILES; do
            read_profiles_conf__include "$p.conf"
        done

        local cb="$1"
        shift

        "$cb" "$@"
    else
        local func="${FUNCNAME:-read_profiles_conf}"

        local cb="${1:?missing 1st arg to ${func}() <cb>}"

        eval "$(__in_installer_env__=1 && read_profiles_conf "$@")"
    fi
}

# Usage: valid_domain <name>
valid_domain()
{
    local name="$1"
    local len=${#name}

    # Shorter than 1 or longer than 63 chars?
    [ $len -ge 1 -a $len -le 63 ] || return
    # Has countiguously ".."?
    [ -n "${name##*..*}" ] || return
    # Begins or ends with "." or "-"
    [ -n "${name##[.-]*}" -a -n "${name%%*[-.]}" ] || return

    echo "$name" | grep -q '^[A-Za-z0-9-]\+$'
}

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

## Setup environment

. '/tmp/.simple-cdd-env'

## Make sure environment is set properly

if [ -z "$SIMPLE_CDD_DIR" ]; then
    echo >&2 "$log_name: \"SIMPLE_CDD_DIR\" is empty"
    exit 1
fi

## Restore $log_name if it was non-empty or set new one

if [ -n "$save_log_name" ]; then
    log_name="$save_log_name"
else
    log_name="$this_dir/"
    if [ -z "${log_name##$SIMPLE_CDD_DIR/*}" ]; then
        # Use path under $SIMPLE_CDD_DIR as prefix
        log_name="${log_name#$SIMPLE_CDD_DIR/}"
    else
        # Not expected to have scripts outside of $SIMPLE_CDD_DIR
        log_name='common/'
    fi
    log_name="$log_name$prog_name"
fi
unset save_log_name

## Source distro-specific bootstrap2.sh

. "$SIMPLE_CDD_DIR/$SIMPLE_CDD_DISTRO/bootstrap2.sh"

# Not exiting nor using ':' to keep return code from bootstrap2.sh
