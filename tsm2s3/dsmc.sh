#!/usr/bin/bash
if [ $# -eq 0 ] ; then
   echo "Usage: $(basename $0) command"
   exit 1
fi
export DSM_DIR=/usr/tivoli/tsm/client/api/bin64
export DSM_CONFIG=/usr/tivoli/tsm/client/api/bin64/dsm.opt.od
export DSM_LOG=/ars/blkb/arstmp
NODE=$(basename $0|tr [:upper:] [:lower:])
case $NODE in
    rba01)
        dsmc $@ -server=SSAM_PROD_BLKB -virtualnode=RBA01 -password=RBA01
        ;;
    blkb_02y|blkb_11y|blkb_unl)
        dsmc $@ -server=SSAM_PROD_BLKB -virtualnode=$NODE -password=client
        ;;
    *)
        echo "Need to be linked as: ln dsmc.sh [RBA01|b2-kd-unlim]";exit 1
        ;;
esac
#dsmc $@ -server=SSAM_TEST_RBA -virtualnode=NODE01 -password=NODE01
