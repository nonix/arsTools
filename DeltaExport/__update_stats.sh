#!/usr/bin/env bash

. ${0%/*}/config.ini

[ $# -lt 1 ] && echo "Usage: $(basename $0) table_name [-r]" && exit 1
[ -z "${DB2_INSTANCE}" ] && echo "ERROR: DB2 profile not set" && exit 1

. ${DB2_PROFILE}

TABLE=$1
REORG=$2
LOG=${CMOD_LOGS}/$(basename $0 .sh).${TABLE}.log
date >> $LOG
db2 -o- -v -z $LOG connect to ${DB2DATABASE:-$DB2_INSTANCE}
[ ! -z "$REORG" ] && db2 -o- -v -z $LOG -t "REORG TABLE $TABLE;"
db2 -o- -v -z $LOG -t "RUNSTATS ON TABLE $TABLE;"
db2 -o- -v -z $LOG -t "RUNSTATS ON TABLE $TABLE FOR INDEXES ALL;"
db2 -o- -v -z $LOG terminate
date >> $LOG
