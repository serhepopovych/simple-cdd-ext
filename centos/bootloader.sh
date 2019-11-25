#!/bin/sh

bootloader()
{
    cat >>"$SIMPLE_CDD/bootloader-ks.txt" <<EOF
# System bootloader configuration
bootloader --append=" zswap.enabled=1 nosmt" --location=mbr --boot-drive=$dst
EOF
}
