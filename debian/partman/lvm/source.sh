#!/bin/sh

# Requires: debconf-set

################################################################################

# Name of the volume group for the new system
debconf-set 'partman-auto-lvm/new_vg_name' "$(tolower "$SIMPLE_CDD_DISTRO")"

# Sourced from debian/partman/run.sh
:
