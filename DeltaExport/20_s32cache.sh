#!/usr/bin/env bash

. ${0%/*}/config.ini

[ $# -ne 1 ] && echo "Usage $0 AGID_NAME" >&2 && exit 1

AGID_NAME="$1"

function ctrl_c() {
  touch stop.aws
  echo "WARN: *** Ctrl-C trapped" >&2
}

trap ctrl_c INT
trap 'rm -f stop.aws' exit

CMND=${CMND:-"./__s3_retrieval.pl ${AGID_NAME}"}

echo "INFO: $0 $@ -- Started at $(date)" >&2
[ -z "${CACHEDIR}" ] && echo -n "WARN: CACHEDIR not defined " >&2
if [ -f "${CMOD_CFG_CACHE}" ] ; then
    export CACHEDIR=${CACHEDIR:-$(ls -1d $(grep -v \# "${CMOD_CFG_CACHE}")/${CMOD_INSTANCE})}
else
    export CACHEDIR=${CACHEDIR:-"${CMOD_CACHE_DIR_SOURCE}"}
fi
echo "using: $CACHEDIR"
IFS=$'\n'
for c in $(eval $CMND) ; do
  [ -f stop.aws ] && break
  eval $c >/dev/null 2>&1 &
  while [ $(jobs -p|wc -l) -ge 48 ] ; do
    wait -n
  done
done

echo "INFO: $0 -- Finished at $(date)" >&2
