#!/bin/sh

# Requires: cat(1), rm(1), dpkg(1)

################################################################################

if [ -z "$SIMPLE_CDD_IN_TARGET" ]; then
    #### Commands in debian-installer environment (system in /target)

    ## Source common helpers

    . '/cdrom/simple-cdd/common/bootstrap.sh'

    # Copy themselve to installed system mounted at /target
    in_target_sh='/tmp/in-target-late_command.sh'

    f="/target/$in_target_sh"
    cat "$this" >"$f" && chmod 0755 "$f"

    # Execute in-target stage
    SIMPLE_CDD_IN_TARGET='y' exec in-target "$in_target_sh" "$@"
else
    #### Commands in system environment (chrooted in /target, no bootstrap.sh)

    ## Exit as long as command pipeline fails

    set -e

    ## Apply "dash dash/sh bool false" preseed

    postinst='/var/lib/dpkg/info/dash.postinst'
    if [ -f "$postinst" -a -x "$postinst" ]; then
        "$postinst" 'postinst'
    fi

    ## Keep systemd-sysv package as default on updates

    echo 'systemd-sysv hold' | dpkg --set-selections ||:

    ## Only cleanup on successful installation

    rm -f "$0" ||:
fi

# Executed from preseed/late_command
exit 0
