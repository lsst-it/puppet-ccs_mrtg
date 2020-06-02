#!/bin/bash

## Return the community from snmpd.conf, else generate one.

conf=/etc/snmp/snmpd.conf

if [ -r $conf ]; then
    community=$(awk '$1 == "com2sec" && $2 == "local" {print $NF}' $conf)
else
    community=
fi

case $community in
    ""|public)
        ## coreutils.
        c=$(dd bs=21 count=1 if=/dev/urandom 2> /dev/null | base64 | tr -d '+/')
        community=${c:0:22}
    ;;
esac

echo "snmp_community=${community}"

exit 0
