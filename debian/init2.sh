#!/bin/sh

# Requires: mkdir, sed, sort, debconf-get, debconf-set, debconf-set-selections

################################################################################

## Load default.preseed to activate simple-cdd-profiles
debconf-set-selections "$SIMPLE_CDD_DIR/default.preseed"

## Update preseed/early_command to execute our early_command.sh hook
early_command_sh="$SIMPLE_CDD_DISTRO_DIR/early_command.sh"

val="$(debconf-get 'preseed/early_command')"
if [ -n "$val" ]; then
    val="$early_command_sh && $val"
else
    val="$early_command_sh"
fi

debconf-set 'preseed/early_command' "$val"

## Update preseed/late_command to execute our late_command.sh hook
late_command_sh="$SIMPLE_CDD_DISTRO_DIR/late_command.sh"

val="$(debconf-get 'preseed/late_command')"
if [ -n "$val" ]; then
    val="$late_command_sh && $val"
else
    val="$late_command_sh"
fi

debconf-set 'preseed/late_command' "$val"

# Sourced from common/init.sh
:
