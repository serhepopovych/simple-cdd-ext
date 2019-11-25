#!/bin/sh

# Requires: sed, tr, sort, debconf-get, debconf-set

################################################################################

## Source common helpers

. '/cdrom/simple-cdd/common/bootstrap.sh'

## Patch old (up to 1.0.114 found in Debian GNU/Linux 10 (buster))
## debootstrap(8) to also apply excludes to required packages.

sed -i '/usr/sbin/debootstrap' \
    -e '/^	base=\$(without "\$base \$ADDITIONAL" "\$EXCLUDE")$/!b
        n
        /^	required=\$(without "\$required" "\$EXCLUDE")$/b
        i\
	required=$(without "$required" "$EXCLUDE")'

## Patch /usr/lib/apt-setup/generators/01setup to add apt(8)
## config file that disables Release file expiration checks.

sed -i '/usr/lib/apt-setup/generators/01setup' \
    -e '/^	>\$ROOT\/etc\/apt\/apt\.conf\.new$/!b
        n
        /^fi$/!b
        a\
\
# no Release file expiry checks\
cat >/target/etc/apt/apt.conf.d/9a-check-valid-until <<_EOF\
// Disable Release file expiry checks\
Acquire::Check-Valid-Until false;\
_EOF'

## Process *.excludes

val="$(debconf-get 'base-installer/excludes')"

val="$(
{
    echo "$val" | tr ' ' '\n'
    for p in $SIMPLE_CDD_PROFILES; do
        f="$SIMPLE_CDD_DIR/$p.excludes"

        # Skip non-existing and empty files
        [ -s "$f" ] || continue

        sed -n -e '/^\s*\(#\|$\)/!p' "$f"
    done
} | sort -u | tr '\n' ' '
)"

debconf-set 'base-installer/excludes' "$val"

# Executed from partman/early_command; now start partman
exec "$SIMPLE_CDD_DISTRO_DIR/partman/run.sh"
