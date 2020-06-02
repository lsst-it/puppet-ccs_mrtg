#!/bin/sh

## FIXME Yuck

cfg=/home/mrtg/mrtg/eth.cfg

if [ -r $cfg ]; then
    sed -n 's/.*MaxBytes.*_\([0-9.]*\)\]: \([0-9]*\)/netspeed_\1=\2/p' $cfg
fi

exit 0
