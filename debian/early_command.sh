#!/bin/sh

# Requires: rm, debconf-set-selections

################################################################################

## Source common helpers

. '/cdrom/simple-cdd/common/bootstrap.sh'

## Helpers and initialization

# Usage: set_selections_add <file> <opt> <dflt_val>
set_selections_add()
{
    local func="${FUNCNAME:-set_selections_add}"

    local file="${1:?missing 1st arg to ${func}() <file>}"
    local opt="${2:?missing 2d arg to ${func}() <opt>}"
    local val="${3:?missing 3rd arg to ${func}() <dflt_val>}"

    val="$(get_cmdline_var "$opt" "$val")"

    echo "d-i $opt string $val" >>"$file"
}

f='/tmp/.simple-cdd-early_command.sh-preseed'

# Make sure preseed file exists and empty. Not deleting
# it on failure to have information for debugging.
: >"$f"

## Preseed mirrors based either on command line options or on profile configs

# Usage: read_profiles_conf_cb__mirrors ...
read_profiles_conf_cb__mirrors()
{
    local method host dir

    eval "$(split_url "$debian_mirror")"
    echo "mirror_proto='$method' mirror_host='$host' mirror_dir='$dir'"

    eval "$(split_url "$security_mirror")"
    echo "sec_host='$host' sec_dir='$dir'"
}

read_profiles_conf 'read_profiles_conf_cb__mirrors'

# Set country explicitly here for manual to make sure choose-mirror
# does not start selecting mirrors based on country as we provide
# explicit one either via commandline (prefferred) or via simple-cdd
# profile configuration files.
set_selections_add "$f" 'mirror/country'          'manual'

set_selections_add "$f" 'mirror/protocol'         "${mirror_proto}"
set_selections_add "$f" 'mirror/http/hostname'    "${mirror_host}"
set_selections_add "$f" 'mirror/http/directory'   "${mirror_dir}"
set_selections_add "$f" 'apt-setup/security_host' "${sec_host}${sec_dir%/}"

## Load generated preseed file

# We cannot use debconf-set here since some preseeds might be
# unavailable at early command execution as templates provided
# by corresponding udebs neither loaded nor present in initrd.
debconf-set-selections "$f"

## Patch postinst scripts for udebs

dpkg_info='/var/lib/dpkg/info'

# Usage: udpkg_pre <exe> ...
udpkg_pre()
{
    # Header
    echo '#!/bin/sh'
    echo
    echo 'set -e'
    echo
    echo 'all="$*"'
    echo
    echo '# Statically created by pre/post script generator'
    echo "dpkg_info='$dpkg_info'"
    echo
    echo '# Dynamically passed via environment by wrapper'
    echo '# HOOKS_DIR, PRE, POST, KEEP, THIS'
    echo
    echo_function_keep
    echo

    # Body
    cat <<'_EOF'
# ethdetect
if [ -z "${all##* --configure *ethdetect*}" ]; then
    # postinst
    f="$dpkg_info/ethdetect.postinst"

    sed -i "$f" \
        -e 's,^exec ethdetect$,lsifaces() {\
    # Based on sed/grep from lsifaces() in ethdetect and netcfg::get_all_ifs()\
    sed -n -e "/\\W*\\(lo\\|sit[0-9]\\+\\):/d;s/^\\s*\\([a-z0-9]\\+\\):\\s*[0-9]*.\\+$/\\1/p" /proc/net/dev\
}\
if ! ethdetect || ! [ -n "$(lsifaces)" ]; then\
    # Disable network entirely if ethernet card detection fails\
    . /usr/share/debconf/confmodule\
    db_set netcfg/enable false\
fi,'

    keep
    exit
fi

# Tell wrapper to keep this hook script
exit 1
_EOF
}

make_wrapper 'udpkg' 'udpkg_pre' '' '1'

## Cleanup

rm -f "$f" ||:

# Executed from preseed/early_command
exit 0
