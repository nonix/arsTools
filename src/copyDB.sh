#!/bin/bash

# LOCDB=LAGARCH
# LOCDBUSR=lagarch
# REMDB=PAGARCH
# REMDBUSR=odadm
# export REMDBPWD=""
# TMPD=/ars/agkb/arstmp
# DB2PROFILE=~lagarch/sqllib/db2profile
# NTH=8


LOCDB=CLARSP1
LOCDBUSR=ondemand
REMDB=CLIPROD
REMDBUSR=ondemand
#export REMDBPWD=""
TMPD=/ars/CopyClientis/arsdb_backup/cli2sc
DB2PROFILE=~ondemand/sqllib/db2profile
NTH=8

: ${REMDBPWD?"ERROR: set the variable and export it!"}

TMPD=$TMPD/d$$

[ $# -lt 1 ] && echo "Usage: $0 tableList.file|(ALL [excludePredicate])" >&2 && exit 1

TS=$(date +%Y%m%d%H%M)
#TSYMD=$(date +%Y-%m-%d\ %H:%M:00)
TSYMD=$(date +%Y-%m-%d)
INSEGLST=$1
if [ "$INSEGLST" == "ALL" ] ; then
  SEGLST=seg.all.${TS}.lst
else
  SEGLST=$1
  [ ! -f $SEGLST ] && echo "ERROR: The list of tables $SEGLST does not exists" && exit 2
fi

EXCLUDE=${2:-1=1}

function intHandler () {
  echo "${1}[$BASHPID]:SIGINT trapped"
  pids=""
  for p in $(jobs -p) ; do
    pids="$pids $p"
  done
  [ ! -z "$pids" ] && kill $pids 2>/dev/null
  sleep 2
  pids=$(jobs -p | xargs -r echo)
  [ ! -z "$pids" ] && kill -9 $pids 2>/dev/null
}

mkdir $TMPD
trap "cd;rm -r $TMPD" exit

function getSegments() {
  eval . $DB2PROFILE
  db2 -o- connect to $REMDB user $REMDBUSR using $REMDBPWD
  db2 -o- -p- -t "export to $SEGLST of DEL modified by nochardel select table_name from 
(select 0 as agid,name as table_name,0 as closed_date,0 as ins_rows,0 as upd_rows,0 as del_rows,null as closed_dt from sysibm.systables where creator=user and name like 'ARS%'
union all
select agid,table_name,closed_date,ins_rows,upd_rows,del_rows,closed_dt from arsseg where agid in (select agid from arsag where name not like 'System%'))
where $EXCLUDE
order by agid;"
  db2 -o- terminate
}

function mkSchema4Table () {
  TABLE=$1
  LOG=$TMPD/${FUNCNAME}_${TABLE}.log
  SQL=$TMPD/${FUNCNAME}_${TABLE}.sql

  eval . $DB2PROFILE

  # Export from remote
  db2look -d $REMDB -dp -e -noimplschema -i $REMDBUSR -w $REMDBPWD -o $TMPD/${TABLE}.sql -tw $TABLE 2>/dev/null
  if [ -f $TMPD/${TABLE}.sql ] ; then
  	export TABLESPACE=$(perl -lne 'print "create tablespace $1;" if /\bIN\b\s+\"(\w+)/' $TMPD/${TABLE}.sql)
	perl -lpe 's/CONNECT\s+TO\s.+$/$ENV{TABLESPACE}/;last if (/CONNECT\s+RESET/)' $TMPD/${TABLE}.sql >$TMPD/${TABLE}.tmp
  rm -f $TMPD/${TABLE}.sql
  mv $TMPD/${TABLE}.tmp $SQL
  else
  	echo "ERROR: Missing object $TABLE in source database"
  fi
  
  # Import to local
  db2 -o- connect to $LOCDB
  db2 -o- -vz $LOG -tf $SQL
  db2 -o- terminate
}

function copyTable () {
  TABLE=$1
  trap 'intHandler $FUNCNAME' INT
  eval . $DB2PROFILE
  CUR=C$TABLE
  LOG=$TMPD/${FUNCNAME}_${TABLE}.log
  db2 -o- connect to $LOCDB
  db2 -o- -tvz $LOG "DECLARE $CUR CURSOR DATABASE $REMDB USER $REMDBUSR USING $REMDBPWD FOR SELECT * FROM ${TABLE} with ur;"
  rc=$?
  if [ $rc -eq 0 ] ; then
    db2 -o- -tvz $LOG "LOAD FROM $CUR OF CURSOR TEMPFILES PATH /tmp REPLACE INTO $TABLE nonrecoverable;"
    rc=$?
  else
   echo "WARNING: Failed to create cursor $CUR for table $TABLE" >&2
  fi
  db2 -o- terminate
  return $rc
}

function purgeExces () {
  eval . $DB2PROFILE
  LOG=$TMPD/${FUNCNAME}.log
  LASTABLES=$TMPD/lastTables.lst
  # Get tables touched since start of copy
  db2 -o- terminate
  db2 -o- connect to $REMDB user $REMDBUSR using $REMDBPWD
  # Just get agids
  db2 -o- -vz $LOG -t "export to $LASTABLES of IXF select * from arsag where last_load_dt >='$TSYMD' and name not like 'System%';"
  db2 -o- terminate
  
  # Purge data exces from segment tables in destination to sync it with ARS tables
  export DB2DBDFT=$LOCDB
  db2 -o- connect to $LOCDB
  db2 -o- -t "drop table NN_TEMP;"
  db2 -o- -tvz $LOG "import from $LASTABLES of IXF create into NN_TEMP;"
  rm -f $LASTABLES
  db2 -o- -vz $LOG -t "export to $LASTABLES of DEL modified by nochardel select (translate(load_id||load_id_suffix,'','0123456789$','')||lpad(translate(load_id||load_id_suffix,'','ABCDEFGHIJKLMNOPQRSTUVWXYZ$',''),7,'0')) as doc0name, agid_name||seg_id as table_name from arsag where nvl(last_load_dt,'1970-01-01')>='$TSYMD' and agid in (select agid from NN_TEMP);"
  db2 -o- -t "drop table NN_TEMP;"
  # Loop for all records and delete all doc_names where >=
  SAVE_IFS=$IFS
  for line in $(cat $LASTABLES);do
    IFS=',' read -r -a rec <<< "$line"
    # ${rec[0]} = doc_name
    # ${rec[1]} = table_name
    db2 -o- -mtvz $TMPD/purge_${rec[1]}.log "delete from ${rec[1]} where trim(left(translate(doc_name,'','0123456789$',''),3)||lpad(translate(doc_name,'','ABCDEFGHIJKLMNOPQRSTUVWXYZ$',''),7,'0')) >= '${rec[0]}';"
  done
  db2 -o- terminate
  IFS=$SAVE_IFS
}
# Friday.March.2024
#
# Main()
#
if [ ! -f $SEGLST ] ; then
  getSegments
fi

typeset -i total=$(cat $SEGLST|wc -l)
typeset -i cnt=0;
echo -e "\nINFO: $0 started at $(date)"
for seg in $(cat $SEGLST) ; do
  echo "copy $seg $(date +%T) ..."
  mkSchema4Table $seg
  ((cnt++))
  copyTable $seg &
  while [ $(jobs -p|wc -l) -gt $NTH ] ; do
    echo -n "... waiting: "
    sleep 1
    wait -n
    echo "$cnt/$total done"
  done
done
echo "Final wait ..."
wait

purgeExces

ALOG=copyDB.${TS}.log
cat $TMPD/mkSchema4Table_*.log $TMPD/copyTable_*.log $TMPD/purgeExces.log >$ALOG
echo "INFO: Log in $ALOG"

if [ "$INSEGLST" == "ALL" ] ; then
  echo "INFO: Folowing manual adjustements should be executed in target system: $LOCDB *before* booting up"
  echo -e "\t1. Delete cache directory (it will get created when OD is booted)"
  echo -e "\t2. Drop all segment tables which belong to System AGs"
  echo -e "\t3. Delete the respected systables from arsseg"
  echo -e "\t4. Reset arsag set seg_id=0 where name like 'System%'\n"
  echo -e "\t5. Optional: "
  echo -e "\t\ta. update stats for ars tables using arsdb -s"
  echo -e "\t\tb. after booting up the OD instance, update stats on segment tables using arsmaint -r"
fi
echo "INFO: Finished $0 at $(date)"
