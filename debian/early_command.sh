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
set_selections_add "$f" 'apt-setup/security_host' "${sec_host}"

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
    # executable
    f='/bin/ethdetect'

    sed -i "$f" \
        -e '/^ethernet_found() {$/!b
            a\
	if [ $# -gt 0 ]; then\
		local delay="$1"\
\
		while ! ethernet_found; do\
			[ $((delay -= 1)) -ge 0 ] || return\
			# Wait for pending events to be prcessed by userspace.\
			#\
			# Has little impact on ethernet interface creation\
			# that is done by kernel space, but could be useful\
			# if kernel modules loaded by hw-detect/load_media\
			update-dev --settle >/dev/null ||:\
			# There is no better option here as some modules\
			# (e.g. virtio_net) loaded by hw-detect call known\
			# to create network device after first call to this\
			# function making them invisible to ethdetect.\
			sleep 1\
		done\
\
		return 0\
	fi\
'
    sed -i "$f" \
        -e 's/^\(while ! ethernet_found\)\(; do\)$/\1 3\2/'

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

# netcfg
if [ -z "${all##* --configure *netcfg*}" ]; then
    # postinst
    f="$dpkg_info/netcfg.postinst"

    sed -i "$f" \
        -e 's,^exec netcfg$,lsaddrs() {\
    # Find both IP and IPv6 addresses of global scope\
    ip -4 -o address show scope global ||:\
    ip -6 -o address show scope global ||:\
}\
if ! netcfg || ! [ -n "$(lsaddrs)" ]; then\
    # Disable network entirely if no global address found\
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

make_wrapper 'udpkg' 'udpkg_pre' '' '2'

## Cleanup

rm -f "$f" ||:

# Executed from preseed/early_command
exit 0
