#!/usr/bin/bash

[ $# -eq 0 ] && echo "Usage: $0 AGID_NAME|sql1[ sql2[ ...]]" && exit 1

LOG=/ars/odadm/NN/S3/MIG/DATA/LOG

function db2exec() {
  . /ars/agarch/sqllib/db2profile
  rm -f ${1}.log
#  db2 -o- -vz ${1}.log connect to ${DB2INSTANCE}
  LOGF=$LOG/$(basename ${1} .sql).log
  db2 +c -o- -mstvz $LOGF -f $1
  perl -lne '{if (/^(DB|SQL)\d+E/) {print "ERROR: $_ in $ARGV";$rc++}}END{exit $rc}' $LOGF
  [ $? -ne 0 ] && echo "WARN: Non zero exit status, please check the $LOGF"
  gzip ${1}
}

for sql in $@ ; do
  [ ! -f $sql ] && sql=DATA/SQL/SC_${sql}.sql
  [ ! -f $sql ] && echo "ERROR: $sql file not found!" >&2 && exit 2
  echo "INFO: Executing ... $sql"
  db2exec $sql &
  sleep 1
  if [ $(jobs -p| wc -l) -ge 8 ] ; then
    echo "INFO: Max number of threads was reached, waiting ..."
    wait -n
  fi  
done
echo "INFO: Waiting for threads to complete ..."
wait
echo "INFO: Done"

