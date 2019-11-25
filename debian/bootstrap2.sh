#!/bin/sh

# Requires: debconf-get, debconf-set

################################################################################

# Usage: debconf_set_seen ...
debconf_set_seen()
{
    $(
        # Mark changes as "seen" to prevent installer from asking interactively
        . /bin/debconf-set "$@" && db_fset "$1" seen true
     )
}

# Sourced from common/bootstrap.sh
:
