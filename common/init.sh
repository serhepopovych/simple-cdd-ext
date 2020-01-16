#!/bin/sh

# Requires: cat, tr, chmod, ln, mkdir, rm, wget

# Make sure we have stable name as we might be executed from pipe or sourced
prog_name='init.sh'

# Make sure logged names are unique
log_name="common/$prog_name"

# Usage: do_fetch <src> <mode> <wget args>
do_fetch()
{
    local func="${FUNCNAME:-do_fetch}"

    local src="${1:?missing 1st arg to ${func}() <src>}"
    shift
    local mode="$1"
    shift

    # Find output target
    local a quiet='/dev/stderr' dst=''
    for a in "$@" ''; do
        case "$a" in
            -O) dst='/' ;;
            -q) [ "$dst" != '/' ] || dst='/dev/null'; quiet='/dev/null' ;;
            *)  [ "$dst" != '/' ] || dst="$a" ;;
        esac
    done
    dst="${dst:-/dev/stdout}"

    # Make sure directory tree exists
    mkdir -p "${dst%/*}" ||:

    # Skip if directory as wget(1) might not support recursive retrieving
    [ -n "${dst%%*/}" ] || return 0

    # Skip if src and dst are the same
    [ ! "$src" -ef "$dst" ] || return 0

    # Fetch entry
    local rc=0

    if [ -z "${src##*://*}" ]; then
        wget "$@" "$src" || rc=$?
    else
        { cat "$src" >"$dst"; } 2>"$quiet" || rc=$?
    fi

    if [ $rc -eq 0 ]; then
        [ -z "$mode" ] || chmod "$mode" "$dst" || rc=$?
    else
        echo >&2 "$log_name: fetching \"$src\" to \"$dst\" failed"
    fi

    return $rc
}

################################################################################

# Note that base environment here initially prepared by <distro>/init.sh code.
# It is expected that at least following variables defined:
#
#   SIMPLE_CDD_URL_BASE   - directory containing root of simple-cdd tree
#                           or empty for root (/) filesystem path
#   SIMPLE_CDD_URL_METHOD - method to fetch from URL base: http, ftp
#                           or empty for local CD/DVD
#   SIMPLE_CDD_DIR        - absolute path to root of simple-cdd tree in
#                           installation environment
#   SIMPLE_CDD_DISTRO     - distribution name (e.g. debian, centos, ...)

## Fetch common/bootstrap.sh first to make sure $SIMPLE_CDD_DIR path created

b='common/bootstrap.sh'
url="$SIMPLE_CDD_URL_BASE/$b"
b="$SIMPLE_CDD_DIR/$b"

do_fetch "$url" '' -q -O "$b" # does not require to be executable: skip chmod

## Prepare empty environment files for common/bootstrap.sh

# environment
e='/tmp/.simple-cdd-env'

rm -f "$e" ||:
: >"$e"

# distro specific bootstrap code
t="$SIMPLE_CDD_DIR/$SIMPLE_CDD_DISTRO/bootstrap2.sh"

if [ ! -r "$t" ]; then
   # this is true only for network (e.g. PXE) setups
   mkdir -p "${t%/*}"
   : >"$t"
fi

## Source (.) common/bootstrap.sh

. "$b"

## Determine simple-cdd profiles (make sure default profile is first)

SIMPLE_CDD_PROFILES="$(get_cmdline_var 'simple-cdd/profiles' 'default' ',')"
SIMPLE_CDD_PROFILES="$(profiles_csv "$SIMPLE_CDD_PROFILES")"

for_each_profile | while read p; do
    f="$p.conf"
    do_fetch "$SIMPLE_CDD_URL_BASE/$f" '' -q -O "$SIMPLE_CDD_DIR/$f" ||:
done

# Usage: read_profiles_conf_cb__auto_profiles <profile> ...
read_profiles_conf_cb__auto_profiles()
{
    if [ -n "${1+x}" ]; then
        # Must be defined by distro specific profile (i.e. distro.conf)
        [ "$1" = 'default' ] || profile_append 'auto_profiles' "$1"
    else
        echo "SIMPLE_CDD_PROFILES='$(profiles_csv "$auto_profiles")'"
    fi
}

read_profiles_conf 'read_profiles_conf_cb__auto_profiles'

# Remove unused profiles config files to keep space clean
p=",$SIMPLE_CDD_PROFILES,"
for f in "$SIMPLE_CDD_DIR"/*.conf; do
    [ -e "$f" ] || continue

    t="${f##*/}" && t="${t%.conf}"
    if [ -n "${p##*,$t,*}" ]; then
        rm -f "$f" 2>/dev/null ||:
    fi
done

## Prepare environment file for common/bootstrap.sh

cat >"$e" <<EOF

# URL base (i.e. simple-cdd/) and wget(1) fetch method (empty for local)
SIMPLE_CDD_URL_METHOD='$SIMPLE_CDD_URL_METHOD'
SIMPLE_CDD_URL_BASE='$SIMPLE_CDD_URL_BASE'

# Local filesystem directory and distro simple-cdd running on
SIMPLE_CDD_DIR='$SIMPLE_CDD_DIR'
SIMPLE_CDD_DISTRO='$SIMPLE_CDD_DISTRO'
SIMPLE_CDD_COMMON_DIR='$SIMPLE_CDD_DIR/common'
SIMPLE_CDD_DISTRO_DIR='$SIMPLE_CDD_DIR/$SIMPLE_CDD_DISTRO'

# Profiles to load
SIMPLE_CDD_PROFILES='$SIMPLE_CDD_PROFILES'
EOF

# More SIMPLE_CDD_* variables might be defined (e.g. shortcuts from other vars)
. "$e"

## Fetch files for each simple-cdd profile

# Templates (mandatory)
f='simple-cdd.templates'
do_fetch "$SIMPLE_CDD_URL_BASE/$f" '' -q -O "$SIMPLE_CDD_DIR/$f"

for_each_profile | while read p; do
    # Extra (includes all simple-cdd scripts)
    f="$p.extra"
    if  do_fetch "$SIMPLE_CDD_URL_BASE/$f" '' -q -O "$SIMPLE_CDD_DIR/$f"; then
        while read f; do
            [ -n "$f" -a -n "${f##\#*}" ] || continue

            url="$SIMPLE_CDD_URL_BASE/$f"
            f="$SIMPLE_CDD_DIR/$f"

            # Do not known what files executable and what are not: make all
            do_fetch "$url" 0755 -q -O "$f" || exit
        done <"$SIMPLE_CDD_DIR/$f" # f="$p.extra"
    fi

    # Post script (might not exist)
    f="$p.postinst"
    url="$SIMPLE_CDD_URL_BASE/$f"
    f="$SIMPLE_CDD_DIR/$f"

    do_fetch "$url" 0755 -q -O "$f" || rm -f "$f"

    # Other files
    for f in \
        'downloads' \
        'excludes' \
        'packages' \
        'preseed' \
        'udebs' \
        #
    do
        f="$p.$f"
        do_fetch "$SIMPLE_CDD_URL_BASE/$f" '' -q -O "$SIMPLE_CDD_DIR/$f" ||:
    done
done

## Cleanup environment

unset p f b e t

## Source distro-specific init2.sh

. "$SIMPLE_CDD_DISTRO_DIR/init2.sh"

# Not exiting nor using ':' to keep return code from init2.sh
