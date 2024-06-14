#!/usr/bin/env bash

. ${0%/*}/config.ini

SOURCEDIR="${CMOD_EXPORT}"
DESTDIR="${CMOD_REMOTE}"

function rcopy() {
  SEG=$1
  ./__sha1sum.sh $SEG
  echo "INFO: rsync $SEG started at $(date)"
  rsync -ai --log-file=${CMOD_LOGS}/rsync.$SEG.log --no-implied-dirs ${SOURCEDIR}/$AGN/$SEG ${DESTDIR}/$AGN/ >/dev/null
  if [ $? -eq 0 ] ; then
    rm -rf ${SOURCEDIR}/$AGN/$SEG
  else
    echo "ERROR: rsync of $SEG"
  fi
  mv ${SOURCEDIR}/$AGN/${SEG}.sha1 ${DESTDIR}/$AGN/
  echo "INFO: rsync $SEG finished at $(date)"
}

[[ $# -lt 1 ]] && echo "Usage: $0 [-n Nthreads] agid_name" >&2 && exit 1

echo "INFO: $0 $@ started at $(date)"

# Parse switches
if [[ "$1" == "-n" ]] ; then
  NTH="-n $2"
  shift;shift
fi

export AGN=$1
export SEGS=/tmp/seg.$$
db2 -o- -z ${CMOD_LOGS}/${0##*/}.log connect to ${DB2_INSTANCE} user ${DB2_USER} using ${DB2_PWD}
db2 -o- -vz ${CMOD_LOGS}/${0##*/}.log -t "export to $SEGS of DEL modified by nochardel select distinct segment from MIG_$AGN where status=1;"
trap 'rm -f $SEGS' exit
db2 -o- terminate
[[ ! -d ${DESTDIR}/$AGN ]] && mkdir ${DESTDIR}/$AGN
unset LIBPATH

for SEG in $(cat $SEGS) ; do
  if [[ -d ${DESTDIR}/$AGN/$SEG ]] ; then
    echo "WARN: $SEG already exported, remove to re-export"
    continue
  fi
  ./__export_segment.sh $NTH $SEG
  wait
  rcopy $SEG &
  [[ -f ${0}.stop ]] && rm ${0}.stop && break
done
wait
echo "INFO: $0 finished at $(date)"
