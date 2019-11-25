#!/bin/sh

# Requires: sed, grep, debconf-set

################################################################################

# Btrfs with mixed metadata and data block groups is used (mkfs.btrfs(8) -M
# option) and compression enabled. System installed into "root" subvolume
# to enable reuse of "/" filesystem as snapshots for LXC rootfs.
#
# Note that Debian currently does not support installation to subvolumes
# as well as configuring mixed medatada and data block groups mode: enable
# this by patching certain configuration files and partman-btrfs format script.
#
# For small installations (i.e. ones that is done on <= 2GB disk) no separate
# boot partition created to save space as modern versions of GRUB 2.x can boot
# from btrfs volume (tested at least with Debian GNU/Linux 7.x (wheezy)).

## Add subvol=root as valid btrfs option
file='/lib/partman/mountoptions/btrfs'
if ! grep -q 'subvol=root' "$file"; then
    echo 'subvol=root' >>"$file"
fi

## Patch format code to use -M option if necessary and create 'root' subvolume

recipe="${SIMPLE_CDD_PARTMAN_RECIPE_FILE##*/}"
[ "$(to_bytes "$recipe")" -ge $((5 * GiB)) ] || opts='-M'

sed -i '/lib/partman/commit.d/50format_btrfs' \
    -e 'N
        s,^\s\+\(mkfs\.btrfs \)\(-f \)\?\(.\+\) \\\s\+\$device \(.\+\)$,				\1\2'"${opts:+$opts }"'\3 \\\
					 $device \4 \&\& \\\
			log-output -t partman --pass-stdout \\\
				mkdir -p /tmp/.simple-cdd-btrfs \&\& \\\
			log-output -t partman --pass-stdout \\\
				mount -t btrfs -o compress $device /tmp/.simple-cdd-btrfs \&\& \\\
			log-output -t partman --pass-stdout \\\
				btrfs subvolume create /tmp/.simple-cdd-btrfs/root \&\& \\\
			log-output -t partman --pass-stdout \\\
				umount /tmp/.simple-cdd-btrfs \&\& \\\
			log-output -t partman --pass-stdout \\\
				rmdir /tmp/.simple-cdd-btrfs || code=$?,;t
	P
	D'

# Sourced from debian/partman/run.sh
:
