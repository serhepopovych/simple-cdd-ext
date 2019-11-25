#!/bin/sh

# Requires: cat

partition()
{
    local size_1gb=$((1 * 1024 * 1024 * 1024))
    local src dst size                            # see eval below

    eval "$(find_src '.discinfo' '/cdrom')"       # src=...
    eval "$(find_dst "$src" $disk)"               # dst=... size=...

    : >"$SIMPLE_CDD"

    cat >>"$SIMPLE_CDD/storage-ks.txt" <<EOF

# Partition clearing information
zerombr
clearpart --drives=$dst --all --disklabel=gpt

# Disk partitioning information
part biosboot         --fstype="biosboot" --ondisk=$dst --size=1
part /boot            --fstype="ext2"     --ondisk=$dst --size=256  --label=BOOT
part /boot/efi        --fstype="efi"      --ondisk=$dst --size=256  --label=ESP
part swap                                 --ondisk=$dst --size=512  --label=SWAP
part btrfs.1742       --fstype="btrfs"    --ondisk=$dst --size=1792 --fsoptions="noatime,compress"
part /var/lib/libvirt --fstype="xfs"      --ondisk=$dst --grow      --fsoptions="noatime"

btrfs none  --data=single --metadata=single --mkfsoptions="-M" --label=centos  btrfs.1742
btrfs /home --subvol --name=home LABEL=centos
btrfs /     --subvol --name=root LABEL=centos
btrfs /var  --subvol --name=var  LABEL=centos
EOF

    echo "INSTALL_SRC='$src' INSTALL_DST='$dst' INSTALL_DST_SIZE='$size'"
}

# Where to find answers file and intallation helpers
[ -n "$SIMPLE_CDD" ] || SIMPLE_CDD='/tmp/.simple-cdd'
[ -d "$SIMPLE_CDD" ] || return

. "$SIMPLE_CDD/common/partman.sh"

partition
