#!/bin/sh

# Requires: rm, debconf-set-selections

################################################################################

## Source common helpers

. '/cdrom/simple-cdd/common/bootstrap.sh'

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

# Usage: set_selections_add <file> <opt> <dflt_val>
set_selections_add()
{
    local func="${FUNCNAME:-set_selections_add}"

    local file="${1:?missing 1st arg to ${func}() <file>}"
    local opt="${2:?missing 2d arg to ${func}() <opt>}"
    local val="${3:?missing 3rd arg to ${func}() <val>}"

    val="$(get_cmdline_var "$opt" "$val")"

    echo "d-i $opt string $val" >>"$file"
}

f='/tmp/.simple-cdd-early_command.sh-preseed'

# Set country explicitly here for manual to make sure choose-mirror
# does not start selecting mirrors based on country as we provide
# explicit one either via commandline (prefferred) or via simple-cdd
# profile configuration files.
set_selections_add "$f" 'mirror/country'          'manual'

set_selections_add "$f" 'mirror/protocol'         "${mirror_proto}"
set_selections_add "$f" 'mirror/http/hostname'    "${mirror_host}"
set_selections_add "$f" 'mirror/http/directory'   "${mirror_dir}"
set_selections_add "$f" 'apt-setup/security_host' "${sec_host}${sec_dir%/}"

# We cannot use debconf-set here since apt-setup/security_host
# isn't loaded at early command execution as template provided
# in apt-setup-udeb which neither loaded nor present in initrd.
debconf-set-selections "$f"

rm -f "$f" ||:

# Executed from preseed/early_command
exit 0
