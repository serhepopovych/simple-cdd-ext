#!/bin/sh

# Requires: grep, cat, cut, readlink, expr, udevadm

[ -z "${__partman_sh__}" ] || return 0
__partman_sh__=1

# Usage: __find_src <marker> [<mountpoint1> <mountpoint2> ...]
__find_src()
{
    local marker="$1"
    shift
    local src='' dev mp

    # Look for local source media: CD/DVD or USB stick
    while [ $# -gt 0 ]; do
        mp="$1"
        shift

        # Skip empty arguments
        [ -n "$mp" ] || continue

        # Has a marker directory entry?
        [ -n "$marker" -a -e "$mp/$marker" ] || continue

        # Is a mountpoint?
        dev="$(grep '[ \t]\+$mp[ \t]\+' /proc/mounts | cut -d ' ' -f 1)"
        [ -n "$dev" ] || continue

        # Has valid device path?
        dev="$(device_info -q path -n "$dev")"
        [ -n "$dev" ] || continue

        # Find parent device in case of device is partition
        # (e.g. when ISO is written and booted from USB stick).
        dev="/sys$dev"
        if [ -f "$dev/partition" ] &&
           [ "$(cat "$dev/partition")" = '1' ]; then
            dev="${dev%/*}"
        fi

        src="/dev/${dev##*/}"
        break
    done

    if [ -z "$src" ]; then
        src="${SIMPLE_CDD_URL_BASE:-/}"
    fi

    # Bailout with /dev/null
    if [ -z "$src" ]; then
        src='/dev/null'
    fi

    echo "src='$src'"
}

# Usage: find_src_once <marker> [<mountpoint1> <mountpoint2> ...]
find_src_once()
{
    if [ -z "$SIMPLE_CDD_SRC" ]; then
        local src
        eval "$(__find_src "$@")"
        SIMPLE_CDD_SRC="$src"
    fi

    echo "src='$SIMPLE_CDD_SRC'"
}

# Usage: __find_dst <src> [<size_min>] [<disk1> <disk2> ...]
__find_dst()
{
    # This might be empty (e.g. in case of network installation)
    local sdev="$1"
    shift

    local size_512mb=$((512 * 1024 * 1024))
    local size_min="$1"
    if [ "$size_min" -ge 0 -o "$size_min" -lt 0 ] 2>/dev/null; then
        shift
        [ $size_min -ge $size_512mb ] || size_min=$size_512mb
    else
        size_min=$size_512mb
    fi

    local genhd_fl_cd=8 # GENHD_FL_CD::include/linux/genhd.h
    local mapdev flags dev size

    for dev in "$@" /dev/disk/by-path/* ''; do
        # Also skips empty entries
        [ -n "${dev##*-part*}" ] || continue

        mapdev="$(mapdevfs "$dev")"
        [ -n "$mapdev" -a -e "$mapdev" ] || continue

        # Skip installation CD/DVD and USB stick
        [ "$mapdev" != "$sdev" ] || continue

        # Look for device sysfs path
        dev="$(device_info -q path -n "$mapdev")"
        [ -n "$dev" ] || continue

        # Skip CD/DVD devices
        dev="/sys$dev"
        if [ -f "$dev/capability" ]; then
            flags="0x$(cat "$dev/capability")"
            if [ $((flags & genhd_fl_cd)) -ne 0 ]; then
                continue
            fi
        fi

        # Skip devices without size attribute or size less than minimal
        if [ -f "$dev/size" ]; then
            size="$(cat "$dev/size")"
            size=$((size * 512))
            if [ $size -lt $size_min ]; then
                continue
            fi

            # Found candidate
            dev="$mapdev"
            break
        fi
    done

    if [ -z "$dev" ]; then
        size=0
    fi

    echo "dst='$dev' size='$size'"
}

# Usage: find_dst_once <src> [<size_min>] [<disk1> <disk2> ...]
find_dst_once()
{
    if [ -z "$SIMPLE_CDD_DST" -o -z "$SIMPLE_CDD_DST_SIZE" ]; then
        local dst size
        eval "$(__find_dst "$@")" # dst=... size=...
        SIMPLE_CDD_DST="$dst"
        SIMPLE_CDD_DST_SIZE="$size"
    fi

    echo "dst='$SIMPLE_CDD_DST' size='$SIMPLE_CDD_DST_SIZE'"
}

# Usage: to_bytes <size>[KB|MB|...|KiB|MiB|...]
to_bytes()
{
    local func="${FUNCNAME:-to_bytes}"

    local size="${1:?missing 1st arg to ${func}() <size>}"
    local unit="$(expr substr "$size" $((${#size} - 2)) 3)"

    unit="${unit#[0-9a-fA-F]}"
    case "$unit" in
        'KB'|'MB'|'GB'|'TB'|'PB'|'EB'|'ZB'|'YB'|\
        'KiB'|'MiB'|'GiB'|'TiB'|'PiB'|'EiB'|'ZiB'|'YiB')
            # $unit should be defined outside of this function
            size="${size%$unit}"
            ;;
        [0-9a-fA-F][0-9a-fA-F])
            # bytes
            local B=1
            unit='B'
            ;;
        *)
            # invalid/unknown
            unit=''
            ;;
    esac

    [ -n "$unit" -a $size -gt 0 ] 2>/dev/null
    local rc=$?

    if [ $rc -eq 0 ]; then
        eval "size=\$((size * $unit))"
    else
        size=0
    fi

    echo $size

    return $rc
}

# Usage: to_human <size> [<SI>|<IEC>]
to_human()
{
    local func="${FUNCNAME:-to_human}"

    local size="${1:?missing 1st arg to ${func}() <size>}"
    [ "$size" -ge 0 ] 2>/dev/null || return

    local type="$2"
    type="$(toupper "$type")"
    case "$type" in
      'SI'|'IEC'|'') ;;
      *) return 1 ;;
    esac

    # SI
    local divisor_SI=1000
    local suffix_SI_0=''
    local suffix_SI_1='KB'
    local suffix_SI_2='MB'
    local suffix_SI_3='GB'
    local suffix_SI_4='TB'
    local suffix_SI_5='PB'
    local suffix_SI_6='EB'
    local suffix_SI_7='ZB'
    local suffix_SI_8='YB'

    # IEC
    local divisor_IEC=1024
    local suffix_IEC_0=''
    local suffix_IEC_1='KiB'
    local suffix_IEC_2='MiB'
    local suffix_IEC_3='GiB'
    local suffix_IEC_4='TiB'
    local suffix_IEC_5='PiB'
    local suffix_IEC_6='EiB'
    local suffix_IEC_7='ZiB'
    local suffix_IEC_8='YiB'

    local suffix_max=8

    if [ -z "$type" ]; then
        [ $((size % divisor_IEC)) -eq 0 ] && type='IEC' || type='SI'
    fi

    local i=0 divisor
    eval "divisor=\$divisor_${type}"

    while [ $size -ge $divisor -a $i -lt $suffix_max ]; do
        size=$((size / divisor))
        i=$((i + 1))
    done

    eval echo "\$size\$suffix_${type}_${i}"
}

# Usage: partman__find_recipe <dir> <size>
partman__find_recipe()
{
    local func="${FUNCNAME:-partman__find_recipe}"

    local dir="${1:?missing 1st arg to ${func}() <dir>}"
    local size="${2:?missing 2d arg to ${func}() <size>}"

    local rbytes_list='' rbytes rsize

    for rsize in "$dir/"*; do
        # Make sure it really exists (i.e. not unresolved '*' or broken symlink)
        [ -s "$rsize" ] || continue

        rsize="${rsize##*/}"

        rbytes=$(to_bytes "$rsize") || continue

        rbytes_list="$rbytes_list$rbytes
"
        eval "local human_${rbytes}='$rsize'"
   done

   for rbytes in $(echo "$rbytes_list" | sort -n -r); do
       if [ $rbytes -le $size ]; then
           eval "echo \"\$human_${rbytes}\""
           return 0
       fi
   done

   if read -r rsize <"$dir/default" && [ -s "$dir/$rsize" ]; then
       echo "$rsize"
       return 0
   fi

   return 1
}

# Usage: partman__find_install_src_and_dst <preferred_disk> <marker> [<mountpoint1> ...]
partman__find_install_src_and_dst()
{
    local func="${FUNCNAME:-partman__find_install_src_and_dst}"

    local preferred_disk="$1"
    local marker="${2:?missing 2d arg to ${func}() <marker>}"
    shift 2

    # Source of installation, might be empty (e.g. in case of network installs)
    local src
    eval "$(__find_src "$marker" "$@")"            # src=...

    # Destination to install
    local dst size
    eval "$(__find_dst "$src" "$preferred_disk")"  # dst=... size=...

    # Make results gloablly available
    SIMPLE_CDD_PARTMAN_SRC="$src"
    SIMPLE_CDD_PARTMAN_DST="$dst"
    SIMPLE_CDD_PARTMAN_DST_SIZE="$size"
}

# Usage: partman__parse_simple_cdd_var <var> <dflt> [<size>] [<file>]
partman__parse_simple_cdd_var()
{
    local func="${FUNCNAME:-partman__parse_simple_cdd_var}"

    # <var>=[{gpt|msdos|default}:][btrfs|lvm|regular][/size]
    #             disklabel           diskschema     disksize
    local var_name="${1:?missing 1st arg to ${func}() <var>}"
    local var_dflt="${2:?missing 2d arg to ${func}() <dflt>}"
    local size="${3:-0}"
    shift 3

    local partman="$(get_cmdline_var "$var_name" "$var_dflt" '' "$@")"
    local disklabel diskschema disksize

    # disklabel
    disklabel="${partman%%:*}"
    if [ "$disklabel" != "$partman" ]; then
        case "$disklabel" in
            'gpt'|'msdos'|'default') ;;
            *) disklabel='' ;;
        esac
    else
        disklabel=''
    fi
    [ -n "$disklabel" ] || disklabel='gpt'

    # diskschema
    diskschema="${partman#*:}"
    diskschema="${diskschema%/*}"
    if [ "$diskschema" != "$partman" ]; then
        case "$diskschema" in
            'btrfs'|'lvm'|'regular') ;;
            *) diskschema=''         ;;
        esac
    else
        diskschema=''
    fi
    [ -n "$diskschema" ] || diskschema='btrfs'

    # disksize
    disksize=$(to_bytes "${partman##*/}") || disksize=$(to_bytes '20GB')
    [ $size -le 0 -o $disksize -le $size ] || disksize=$size

    # Make results globally available
    SIMPLE_CDD_PARTMAN_DISKLABEL="$disklabel"
    SIMPLE_CDD_PARTMAN_DISKSCHEMA="$diskschema"
    SIMPLE_CDD_PARTMAN_DISKSIZE="$disksize"
}

# Usage: partman__make_environment
partman__make_environment()
{
    local recipe_dir recipe

    SIMPLE_CDD_DISTRO_PARTMAN_DIR="$SIMPLE_CDD_DISTRO_DIR/partman"
    SIMPLE_CDD_DISTRO_PARTMAN_SCHEMA_DIR=\
"$SIMPLE_CDD_DISTRO_PARTMAN_DIR/$SIMPLE_CDD_PARTMAN_DISKSCHEMA"

    recipe_dir="$SIMPLE_CDD_DISTRO_PARTMAN_SCHEMA_DIR"
    recipe="$(partman__find_recipe "$recipe_dir" "$SIMPLE_CDD_PARTMAN_DISKSIZE")"
    SIMPLE_CDD_PARTMAN_RECIPE_FILE="$recipe_dir/$recipe"
    SIMPLE_CDD_PARTMAN_RECIPE=\
"$SIMPLE_CDD_PARTMAN_VAR/$SIMPLE_CDD_PARTMAN_DISKSCHEMA/$recipe"

    cat >>'/tmp/.simple-cdd-env' <<EOF

# Partition manager (partman)
SIMPLE_CDD_PARTMAN_MARKER='$SIMPLE_CDD_PARTMAN_MARKER'
SIMPLE_CDD_PARTMAN_MNT='$SIMPLE_CDD_PARTMAN_MNT'

SIMPLE_CDD_PARTMAN_VAR='$SIMPLE_CDD_PARTMAN_VAR'
SIMPLE_CDD_PARTMAN_VAL_DFLT='$SIMPLE_CDD_PARTMAN_VAL_DFLT'

SIMPLE_CDD_PARTMAN_DISKLABEL='$SIMPLE_CDD_PARTMAN_DISKLABEL'
SIMPLE_CDD_PARTMAN_DISKSCHEMA='$SIMPLE_CDD_PARTMAN_DISKSCHEMA'
SIMPLE_CDD_PARTMAN_DISKSIZE='$SIMPLE_CDD_PARTMAN_DISKSIZE'

SIMPLE_CDD_PARTMAN_SRC='$SIMPLE_CDD_PARTMAN_SRC'
SIMPLE_CDD_PARTMAN_DST='$SIMPLE_CDD_PARTMAN_DST'
SIMPLE_CDD_PARTMAN_DST_SIZE='$SIMPLE_CDD_PARTMAN_DST_SIZE'

SIMPLE_CDD_DISTRO_PARTMAN_DIR='$SIMPLE_CDD_DISTRO_PARTMAN_DIR'
SIMPLE_CDD_DISTRO_PARTMAN_SCHEMA_DIR='$SIMPLE_CDD_DISTRO_PARTMAN_SCHEMA_DIR'

SIMPLE_CDD_PARTMAN_RECIPE_FILE='$SIMPLE_CDD_PARTMAN_RECIPE_FILE'
SIMPLE_CDD_PARTMAN_RECIPE='$SIMPLE_CDD_PARTMAN_RECIPE'
EOF
}

################################################################################

# Note that SIMPLE_CDD_PARTMAN_DST, SIMPLE_CDD_PARTMAN_MARKER and
# SIMPLE_CDD_PARTMAN_MNT should be defined by distro specific code.

SIMPLE_CDD_PARTMAN_VAR="${SIMPLE_CDD_PARTMAN_VAR:-simple-cdd/partman}"
SIMPLE_CDD_PARTMAN_VAL_DFLT="${SIMPLE_CDD_PARTMAN_VAL_DFLT:-gpt:btrfs/20GB}"

. '/cdrom/simple-cdd/common/bootstrap.sh'

## Define some useful constants and helpers

# SI
KB=$((1000))
MB=$((1000 * KB))
GB=$((1000 * MB))
TB=$((1000 * GB))
PB=$((1000 * TB))
EB=$((1000 * PB))
ZB=$((1000 * EB))
YB=$((1000 * ZB))

# IEC
KiB=$((1024))
MiB=$((1024 * KiB))
GiB=$((1024 * MiB))
TiB=$((1024 * GiB))
PiB=$((1024 * TiB))
EiB=$((1024 * PiB))
ZiB=$((1024 * EiB))
YiB=$((1024 * ZiB))

# Usage: device_info ...
if [ -d '/sys/block' ] && type udevadm >/dev/null 2>&1; then
    device_info() { udevadm info "$@"; }
else
    device_info() { :; }
fi

# Usage: mapdevfs <devfs_path>
if ! type mapdevfs >/dev/null 2>&1; then
    mapdevfs() { readlink -f "$1"; }
fi

## Find source and destination of installation

partman__find_install_src_and_dst \
    "$SIMPLE_CDD_PARTMAN_DST" \
    "$SIMPLE_CDD_PARTMAN_MARKER" \
     $SIMPLE_CDD_PARTMAN_MNT

## Parse command line options

partman__parse_simple_cdd_var \
    "$SIMPLE_CDD_PARTMAN_VAR" \
    "$SIMPLE_CDD_PARTMAN_VAL_DFLT" \
    "$SIMPLE_CDD_PARTMAN_DST_SIZE"

## Update environment

partman__make_environment

:
