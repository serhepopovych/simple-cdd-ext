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

## Patch  to avoid forcing apt-getup/mirror/error Retry with
## respect to default value from template or preseeded by the user.

sed -i '/usr/lib/apt-setup/generators/50mirror' \
    -e '/^		db_set apt-setup\/mirror\/error Retry$/d'

sed -i '/usr/lib/apt-setup/generators/60local' \
    -e '/^				db_set apt-setup\/local\/key-error Retry$/d'

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
_EOF\
# no Release.gpg checks (github::simple-cdd-meta issue #5)\
cat >/target/etc/apt/apt.conf.d/9b-allow-insecure-repositories <<_EOF\
// Allow unsigned repositories\
Acquire::AllowInsecureRepositories true;\
_EOF'

## Patch /usr/lib/apt-setup/generators/* to check if network enabled and
## silently ignore mirror verification errors as these are meaningless at all.

for f in '50mirror' '91security' '92updates' '93backports'; do
    f="/usr/lib/apt-setup/generators/$f"
    [ -r "$f" ] || continue

    # Do not assume that network can only be configured by DHCP
    sed -i "$f" \
        -e 'N
            s/^\(\s*\)if db_get netcfg\/dhcp_options && \\\
\s\+\[ "\$RET" = "Do not configure the network at this time" \]; then$/\1if db_get netcfg\/enable \&\& [ "$RET" = false ]; then/;t
            P
            D'

    # Do not notify about mirror verification errors
    sed -i "$f" \
        -e '/^		db_subst apt-setup\/service-failed HOST "\$host"$/,/^		fi$/ d'
done

## Patch /usr/lib/apt-setup/generators/91security to add /debian-security
## to http://${apt-setup/security_host} URL when necessary (wheezy, jessie).

sed -i '/usr/lib/apt-setup/generators/91security' \
    -e 's,\(\(^\|\s\+\)echo\s\+"\S\+\)\(\s*http://\$host\)/*\(\s\+\|"\),\1\3/debian-security\4,'

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

## Process *.pkgsel

val="$(debconf-get 'pkgsel/include')"

val="$(
{
    echo "$val" | tr ' ' '\n'
    for p in $SIMPLE_CDD_PROFILES; do
        f="$SIMPLE_CDD_DIR/$p.pkgsel"

        # Skip non-existing and empty files
        [ -s "$f" ] || continue

        sed -n -e '/^\s*\(#\|$\)/!p' "$f"
    done
} | sort -u | tr '\n' ' '
)"

debconf-set 'pkgsel/include' "$val"

# Executed from partman/early_command; now start partman
exec "$SIMPLE_CDD_DISTRO_DIR/partman/run.sh"
