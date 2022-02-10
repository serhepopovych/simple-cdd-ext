#!/bin/sh

# Requires: sed, grep, debconf-set

################################################################################

# Btrfs with mixed metadata and data block groups is used (mkfs.btrfs(8) -M
# option) and compression enabled. System installed into "@rootfs" subvolume
# to enable reuse of "/" filesystem with snapshots for LXC or systemd-nspawn(1)
# rootfs.
#
# Note that Debian currently does not support installation to subvolumes
# as well as configuring mixed medatada and data block groups mode: enable
# this by patching certain configuration files and partman-btrfs format script.
#
# For small installations (i.e. ones that is done on <= 2GB disk) no separate
# boot partition created to save space as modern versions of GRUB 2.x can boot
# from btrfs volume (tested at least with Debian GNU/Linux 7.x (wheezy)).

## Patch format code to use -M option if necessary and create 'root' subvolume

recipe="${SIMPLE_CDD_PARTMAN_RECIPE_FILE##*/}"
[ "$(to_bytes "$recipe")" -ge $((5 * GiB)) ] || opts='-M'

# partman-btrfs
#   c432c116e9ba Extend description of subvol support, close bug, update date stamp
#   500ee0c6f6ed Add minimal subvolume support for /.
sed -i '/lib/partman/fstab.d/btrfs' \
    -e '/if \[ "\$mountpoint" = "\/tmp" \]; then/,$ b
        /if \[ "\$mountpoint" = \/tmp \]; then/,/echo "\$path" "\$mountpoint" btrfs \$options/c\
			if [ "$mountpoint" = "/tmp" ]; then\
				rm -f $id/options/noexec\
			fi\
			if [ "$mountpoint" = "/" ]; then\
				options="$(get_mountoptions $dev $id),subvol=@rootfs"\
			else\
				options=$(get_mountoptions $dev $id)\
			fi\
			# There is no btrfs fsck\
			echo "$path" "$mountpoint" btrfs $options 0 0'

sed -i '/lib/partman/mount.d/70btrfs' \
    -e '/# import workaround from Kali'\''s partman-btrfs commit:7f43d2c/,$ b
        /mount -t btrfs \${options:+-o "\$options"} \$fs \/target\$mp || exit 1/,/echo "umount \/target\$mp"/c\
	# import workaround from Kali'\''s partman-btrfs commit:7f43d2c\
	options="${options%,subvol=*}"\
	#for removing the option subvol,when thats the only option\
	#eg: options=="subvol=@", no comma present\
	options="${options%subvol=*}"\
	mount -t btrfs ${options:+-o "$options"} $fs /target"$mp" || exit 1\
	if [ $mp = / ]; then\
	    btrfs subvolume create /target$mp/@rootfs\
	    chmod 755 /target$mp/@rootfs\
	    umount /target$mp\
	    options="${options:+$options,}subvol=@rootfs"\
	    mount -t btrfs -o $options $fs /target$mp\
	fi\
	echo "umount /target$mp"'

sed '/lib/partman/commit.d/50format_btrfs' \
    -e 'N
	s,^\(\s\+mkfs\.btrfs \)\(-f \)\?\(.\+ \\\s\+\$device .\+\)$,\1\2'"${opts:+$opts }"'\3,;t
	P
	D'

# Sourced from debian/partman/run.sh
:
