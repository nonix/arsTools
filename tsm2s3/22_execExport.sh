#!/bin/bash
[ $# -ne 1 ] && echo "Usage: $0 AGID_NAME" >&2 && exit 1
AGID_NAME=$1
NTH=20
NTHF=$(basename $0 .sh).nth
STOPF=$(basename $0 .sh).stop
shopt -s expand_aliases
alias date="/ars/odadm/bin/date +'%F %T'"

echo "INFO: $(date) -- Started exporting $AGID_NAME with $NTH threads"
[ ! -d DATA/DOC/$AGID_NAME ] && mkdir DATA/DOC/$AGID_NAME 
for l in ${AGID_NAME}*.lst ; do 
  n=$(echo $l|cut -f2 -d'.');
  (yes 4 2>/dev/null|$n ret -replace=no -filelist=$l DATA/DOC/$AGID_NAME/ >$(basename $l .lst).log 2>&1) &
  if [ $(jobs -p|wc -l) -ge $NTH ] ; then
    wait -n
    if [ -f $NTHF ] ; then
      export NTH=$(cat $NTHF)
      rm $NTHF
      echo "WARN: $(date) -- Number of threads changed to $NTH"
    fi
    if [ -f $STOPF ] ; then
      echo "WARN: $(date) -- Stop requested"
      rm $STOPF
      break
    fi
  fi
done
echo "INFO: $(date) -- Final wait ..."
wait
echo "INFO: $(date) -- Error check ..."
perl -lne 'print $_ if /^ANS\d+[WE]/' ${AGID_NAME}*.log
cat ${AGID_NAME}*.log | perl -lne "print \$1 if /^ANS4035W.+?\'(.+?)\'/" >${AGID_NAME}.redo
if [ $(cat ${AGID_NAME}.redo|wc -l) -gt 0 ] ; then
  echo "INFO: $(date) -- Re-do ..."
  yes 4 2>/dev/null|$n ret -replace=no -filelist=$l DATA/DOC/$AGID_NAME/ >${AGID_NAME}.redo.log 2>&1
else
  rm ${AGID_NAME}.redo
fi
if [ $(cat ${AGID_NAME}*.log|perl -lne 'print $_ if /^ANS\d+[WE]/'|wc -l) -eq 0 ] ; then
  mv ${AGID_NAME}*.{lst,log} DATA/LOG/
  ls -1 DATA/DOC/${AGID_NAME}/ | ./updateSC.pl ${AGID_NAME} 1
else
  echo "ERROR: $(date) -- Some errors detected, check and re-run updateSC.pl" 
fi
echo "INFO: $(date) -- Finished exporting $AGID_NAME"
sms2nn "Finished exporting $AGID_NAME"
