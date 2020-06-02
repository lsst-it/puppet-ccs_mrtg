#!/bin/bash

shopt -s extglob

## Facter mountpoints.m.size_bytes tells us the size in bytes,
## but not the inodes.
for m in / /data /home /opt /scratch /tmp /var ; do

    if [ "$m" == "/" ]; then
        mount=root
    else
        mount=${m#/}
        mount=${mount//\//_}
    fi

    { [ -d "$m" ] && grep -q "$m " /etc/mtab ;} || continue

    inodes=$(df --output=itotal $m | tail -n 1)
    printf "inodes_%s=%s\n" "$mount" "${inodes##+( )}"

done


exit 0
