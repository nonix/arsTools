#!/usr/bin/env bash

. ${0%/*}/config.ini

[ $# -lt 1 ] && echo "Usage: $0 agid_name|segment" >&2 && exit 1
if [ -z "$ROOT" ] ; then
  ROOT=${CMOD_EXPORT}
  echo "WARN: ROOT not set using: $ROOT" >&2
fi
AGN=${1:0:3}
SEGMENT=${1:3}
SEGMENT=${SEGMENT:+${AGN}$SEGMENT}

NTH=8   # Number of parallel threads
[ ! -d $ROOT ] && echo "ERROR: Root dir $ROOT does not exists!" >&2 && exit 2
cd $ROOT/$AGN
TMPD=/tmp/sha1.$$
mkdir $TMPD
trap 'rm -rf $TMPD' exit

# Get list of all SEGMENTS
if [ -z "$SEGMENT" ] ; then
  ls -1d ???[123456789]* |perl -lne "print if (/$AGN\d+$/ && -d )" |sort >$TMPD/AG
else
  echo $SEGMENT >$TMPD/AG
fi

# Calculate sha1 sum using openssl
for a in $(cat $TMPD/AG) ; do
  # Skip if sha1 file exists
  if [ -f ${a}.sha1 ] ; then
    echo "WARN: ${a}.sha1 exists, remove to recalculate" >&2
    continue
  fi

  echo "Computing $a ..."
  typeset -i c=0
  for f in $(find $a -type f) ; do
    ((c++))
    echo -n $f >$TMPD/$c.sha1
    (cat $f | openssl sha1 >>$TMPD/$c.sha1) &
    while [ $(jobs -p|wc -l) -ge $NTH ] ; do
      wait -n
    done
  done
  wait
  echo $TMPD/*.sha1 | xargs perl -lne '/^(.+?)\(stdin\)=\s+(\S+)/;print "$2\t$1"'  >$a.sha1
  echo $TMPD/*.sha1 | xargs rm -f
done
