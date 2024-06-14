#!/usr/bin/env bash

. ${0%/*}/config.ini

NTH=8
[ $# -lt 1 ] && echo "Usage: $(basename $0) [-n #thr (default:$NTH)] segment" && exit 1
if [ "$1" == "-n" ] ; then
  NTH=$2
  shift;shift
fi

SEG=$1
PID=$(basename $0 .sh).pid
PARTS=$(ls -1 ${CMOD_PARS}/${SEG}.*.par | wc -l)
echo "Start: $(date) export of $SEG with $PARTS part(s) by $NTH threads."
echo $$ >$PID
trap 'rm $PID' exit

trap ctrl_c INT

function ctrl_c() {
  echo "** Trapped CTRL-C"
  kill $(jobs -p)
  exit 4
}

function do_export() {
  p=$1
  arsdoc get -h ${CMOD_INSTANCE} -F $p
  rc=$?
  [ $rc -ne 0 ] && echo "WARN: $p rc=$rc; pid=$$" >&2
}

for p in $(ls -1 ${CMOD_PARS}/${SEG}.*.par | sort -n -t\. -k2,2) ; do
  echo -n "$p: $(date +%T): "
  dir=$(head -1 $p | perl -lne 'print $1 if /\[-d\s+(\S+?)\s*\]/')
  # Skip if dir exists; to re-do remove the dir first
  [ -d $dir ] && echo " skip" && continue
  mkdir -p $dir
  do_export $p &
  echo $!
  sleep 1
  while [ $(jobs -p|wc -l) -ge $NTH ] ; do
    wait -n
  done
done
echo "... final wait"
wait
echo "Finished: $(date) with $SEG segment"
