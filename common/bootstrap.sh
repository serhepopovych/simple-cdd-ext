#!/bin/sh

# Requires: mkdir, rmdir, rm, chmod, mv, cat, tr, sed, sort

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

# Usage: profiles_list [<profile|csv_profiles> ...]
profiles_list()
{
    if [ -z "${ifs_pl+x}" ]; then
        local ifs_pl="$IFS"
        IFS=','
        set -- $*
        # Get rid of ,, (empty profile names). Note that IFS='' is not portable.
        IFS='
'
        profiles_list $@
    else
        IFS=','
        local profiles="$*"
        IFS="$ifs_pl"

        profiles="$(subst "$profiles," 'default,')"
        profiles="${profiles%,}"
        profiles="default${profiles:+,$profiles}"

        IFS=','
        local p=''
        for profiles in $profiles; do
            p="${p:+$p }'$profiles'"
        done
        IFS="$ifs_pl"

        echo "$p"
    fi
}

# Usage: profiles_csv [<profile|csv_profiles> ...]
profiles_csv()
{
    eval set -- $(profiles_list "$@")

    local ifs="$IFS"
    IFS=','
    echo "$*"
    IFS="$ifs"
}

# Usage: for_each_profile [<cb>] [<profile|csv_profiles> ...]
for_each_profile()
{
    local fep_cb='echo'
    if [ $# -gt 0 ]; then
        [ -z "$1" ] || fep_cb="$1"
        shift
    fi
    [ $# -gt 0 ] || set -- "$SIMPLE_CDD_PROFILES"

    eval "set -- $(profiles_list "$@")"
    while [ $# -gt 0 ]; do
       "$fep_cb" "$1"
       shift
    done
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
        local cb="$1"
        shift

        # Protect against of "$@" modification by "set" by foregin code
        read_profiles_conf__include()
        {
            local p="./$1"

            [ -r "$p" ] || return

            local cb
            set -- && . "$p" || exit
        }

        cd "$SIMPLE_CDD_DIR"

        read_profiles_conf__cb()
        {
            read_profiles_conf__include "$1.conf" && "$cb" "$1" ||:
        }
        for_each_profile 'read_profiles_conf__cb'

        "$cb"
    else
        local func="${FUNCNAME:-read_profiles_conf}"

        local cb="${1:?missing 1st arg to ${func}() <cb>}"
        local out

        out="$(__in_installer_env__=1 && read_profiles_conf "$1")"
        eval "$out"
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

# Usage: rights_human2octal <rights>
rights_human2octal()
{
    local func="${FUNCNAME:-rights_human2octal}"

    # rwxr-xr-x (755), rwsrwSrwT (7766)
    local rights="${1:?missing 1st arg to ${func}() <rights>}"
    [ ${#rights} -eq 9 ] || return

    local val=0
    local g v s c C r

    # groups: 3  2  1  0
    # bits:  sgtrwxrwxrwx
    for g in 2 1 0; do
        v=0
        s=0

        if [ $g -ge 1 ]; then
            c='s' && C='S'
        else
            c='t' && C='T'
        fi

        r="${rights#[r-][w-][xsStT-]}"
        r="${rights%$r}"

        # [r-]
        case "$r" in
            r??)  v=$((4 + v)) ;;
            -??)  ;;
            *)    return 1 ;;
        esac

        # [w-]
        case "$r" in
            ?w?)  v=$((2 + v)) ;;
            ?-?)  ;;
            *)    return 1 ;;
        esac

        # [xsStT-]
        case "$r" in
            ??x)  v=$((1 + v)) ;;
            ??$c) v=$((1 + v)) && s=$((1 << g)) ;;
            ??$C) s=$((1 << g)) ;;
            ??-)  ;;
            *)    return 1 ;;
        esac

        val=$((val | v << (3 * g) | s << (3 * 3)))

        rights="${rights#$r}"
    done

    printf '%04o\n' "$val"
}

# Usage: file_rights_human <file>
file_rights_human()
{
    local func="${FUNCNAME:-file_rights_human}"

    local file="${1:?missing 1st arg to ${func}() <file>}"

    [ -e "$file" ] || return

    set -- $(ls -l "$file") || return

    local rights="$1"
    rights="${rights#?}"
    [ ${#rights} -eq 9 ] || rights="${rights%?}"

    case "$rights" in
       [r-][w-][xsS-][r-][w-][xsS-][r-][w-][xtT-]) ;;
       *) return 1 ;;
    esac

    echo "$rights"
}

# Usage: file_rights_octal <file>
file_rights_octal()
{
    local func="${FUNCNAME:-file_rights_octal}"

    local file="${1:?missing 1st arg to ${func}() <file>}"

    local rights

    rights="$(file_rights_human "$file")" || return
    rights_human2octal "$rights"
}

# Usage: make_wrapper <bin> [<pre_func>] [<post_func>] [<keep>]
make_wrapper()
{
    local func="${FUNCNAME:-make_wrapper}"

    local bin="${1:?missing 1st arg to ${func}() <bin>}"
    bin="$(command -v "$bin")" && [ -z "${bin##/*}" ] || return

    local exe="${bin}.exe"
    local rights

    # Get permissions
    rights="$(file_rights_octal "$bin")" || return

    # Original binary
    mv -f "$bin" "$exe" || return

    # Create wrapper file
    : >"$bin" || return
    chmod "$rights" "$bin" || return

    # Create hooks, if any
    local hooks_dir="/tmp/${bin##*/}-hooks"
    local keep="$hooks_dir/.keep"

    mkdir -p "$hooks_dir" || return

    if [ -n "$2" ]; then
        local pre="$hooks_dir/pre"
        "$2" >"$pre"  && [ -s "$pre" ] && chmod 0755 "$pre" || rm -f "$pre"
    fi
    if [ -n "$3" ]; then
        local post="$hooks_dir/post"
        "$3" >"$post" && [ -s "$post" ] && chmod 0755 "$post" || rm -f "$post"
    fi

    if ! rmdir "$hooks_dir" 2>/dev/null; then
        [ -z "$4" ] || echo "$4" >"$keep" || return
    fi

    # Header
    cat >>"$bin" <<_EOF
#!/bin/sh

bin='$bin'
exe='$exe'

hooks_dir='$hooks_dir'
keep='$keep'
pre=''
post=''

_EOF

    # Body
    cat >>"$bin" <<'_EOF'
set -e

exit_handler()
{
    local rc=$?

    set +e

    if [ -e "$keep" ]; then
        :
    else
        [ -z "$pre" ] || rm -f "$pre" ||:
        [ -z "$post" ] || rm -f "$post" ||:
        rmdir "$hooks_dir" 2>/dev/null ||:
    fi

    return $rc
}
trap exit_handler EXIT

# Usage: run_hook <hook> ...
run_hook()
{
    local hook="$1"
    shift

    [ -x "$hook" ] || return 0

    local HOOKS_DIR PRE POST KEEP THIS

    HOOKS_DIR="$hooks_dir" \
    PRE="$pre" \
    POST="$post" \
    KEEP="$keep" \
    THIS="$hook" \
        "$hook" "$@"
}

#### Execute real binary

pre="$hooks_dir/pre" && run_hook "$pre" "$exe" "$@" || pre=''

"$exe" "$@"

post="$hooks_dir/post" && run_hook "$post" "$exe" "$@" || post=''
_EOF
}

# Usage: echo_function_keep ...
echo_function_keep()
{
    # This will be a part of pre/post scripts
    cat <<'_EOF'
# Usage: keep ...
keep()
{
    local refcnt rc

    if ! read -r refcnt <"$KEEP" >/dev/null 2>&1 ||
       { refcnt=$((refcnt - 1)) && [ $refcnt -le 0 ]; }; then
        rm -f "$KEEP" ||:
        rc=0 # remove hooks
    else
        echo $refcnt >"$KEEP" ||:
        rc=1 # keep hooks
    fi

    return $rc
}
_EOF
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
