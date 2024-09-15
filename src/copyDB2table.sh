#!/usr/bin/bash
SRCSCH=$DB2INSTANCE
SRCUSR=odlahd01
SRCPWD=nony2000
SRCDB2=$DB2INSTANCE

DSTSCH=$DB2INSTANCE
DSTUSR=
DSTPWD=
DSTDB2=$DB2INSTANCE
export DB2DBDFT=$DSTDB2

function mkSchema() {
local SRC=$1; export SRC
local DST=$2; export DST
export DSTSCH
TMP=/tmp/${SRC}.sql
trap 'rm -f $TMP' exit
db2look -d $SRCDB2 -z $SRCSCH -e -tw $SRC 2>/dev/null|\
perl -0777 -lne '/CREATE TABLE.+?(\(.*?;)/s;$s=$1;$s=~s/(\)\s+IN\s+)\"(\S+?)\"(.+)/$1$ENV{DSTSCH}_$ENV{DST} $3/s;print "CREATE TABLESPACE $ENV{DSTSCH}_$ENV{DST};\nCREATE TABLE $ENV{DST} ",$s,"\n"' >$TMP
db2 -o- -tvsz mkSchema.log -f $TMP 
}

function copyTable() {
local SRC=$1; export SRC
local DST=$2; export DST
db2 -o- -tmsvz ${SRC}.log "DECLARE C$SRC CURSOR DATABASE $SRCDB2 USER $SRCUSR USING $SRCPWD FOR SELECT * FROM $SRCSCH.$SRC with ur"
db2 -o- -tmsvz ${SRC}.log "LOAD FROM C$SRC OF CURSOR TEMPFILES PATH /tmp REPLACE INTO $DST nonrecoverable"
}

[ $# -ne 1 ] && echo "Usage: $0 tblListFile" >&2 && exit 1
db2 connect to $DSTDB2
for tbl in $(cat $1) ; do

mkSchema $tbl NN_$tbl
echo "INFO: Copying table $tbl ..."
[ $? -eq 0 ] && copyTable  $tbl NN_$tbl &
[ $(jobs -p|wc -l) -ge 1 ] && echo "INFO: ... waiting" && wait -n

done
db2 terminate