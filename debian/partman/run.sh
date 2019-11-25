#!/bin/sh

# Requires: cat, sed, grep, debconf-get, debconf-set

################################################################################

## Prepare environment for common/partman.sh

# Marker file/directory to look at source mountpoint(s)
SIMPLE_CDD_PARTMAN_MARKER='.disk/info'
# Installation source mountpoint(s) (space separated)
SIMPLE_CDD_PARTMAN_MNT='/cdrom'
# Initial installation destination; preferred if given
SIMPLE_CDD_PARTMAN_DST="$(debconf-get 'partman-auto/disk')"
disk="$SIMPLE_CDD_PARTMAN_DST"

## Source common helpers

. '/cdrom/simple-cdd/common/bootstrap.sh'
. '/cdrom/simple-cdd/common/partman.sh'

## Setup disk partition and bootloader

if [ -n "$SIMPLE_CDD_PARTMAN_DST" ]; then
    if [ "$SIMPLE_CDD_PARTMAN_DST" != "$disk" ]; then
        debconf-set 'partman-auto/disk' "$SIMPLE_CDD_PARTMAN_DST"
    fi
else
    # We accept SIMPLE_CDD_PARTMAN_DST == "" as non-fatal to give chance
    # debian-installer as partman-auto/disk might be set to something valid
    # that we do not recognize.
    #
    # Same applies when applying grub-installer/bootdev settings.
    :
fi

## Use destination device as device where to install bootloader

if [ -z "$(debconf-get 'grub-installer/bootdev')" ]; then
    # We only touch bootloader target device settings when they
    # not explicitly listed in preseed.
    #
    # This is to respect case when SIMPLE_CDD_PARTMAN_DST == "" but
    # preseed configured partman-auto/disk and grub-installer/bootdev
    # to something valid that we just cannot recognize.
    debconf_set_seen \
        'grub-installer/bootdev' "${SIMPLE_CDD_PARTMAN_DST:-default}"
fi

## Set disklabel type (i.e. msdos, gpt, default)

disklabel="$SIMPLE_CDD_PARTMAN_DISKLABEL"

debconf-set 'partman-basicfilesystems/choose_label'  "$disklabel"
debconf-set 'partman-basicfilesystems/default_label' "$disklabel"
debconf-set 'partman-partitioning/choose_label'      "$disklabel"
debconf-set 'partman-partitioning/default_label'     "$disklabel"
debconf-set 'partman/choose_label'                   "$disklabel"
debconf-set 'partman/default_label'                  "$disklabel"

## Set partitioning method (i.e. regular, lvm, crypto)

diskschema="$SIMPLE_CDD_PARTMAN_DISKSCHEMA"

case "$diskschema" in
    'btrfs') diskmethod='regular' ;;
    *)       diskmethod="$diskschema" ;;
esac

debconf-set 'partman-auto/method'                    "$diskmethod"

## Set recipe to use

debconf-set 'partman-auto/expert_recipe_file' \
    "$SIMPLE_CDD_PARTMAN_RECIPE_FILE"

# This can be used in 'partman/late_command' using debconf-get
# to detect on what partitioning schema is used (e.g. to create
# more subvolumes for btrfs).
debconf-set 'partman-auto/choose_recipe' \
    "$SIMPLE_CDD_PARTMAN_RECIPE"

## Source schema specific configuration

. "$SIMPLE_CDD_DISTRO_PARTMAN_SCHEMA_DIR/source.sh"

# Executed from partman/early_command
exit 0
