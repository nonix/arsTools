#!/usr/bin/bash
export DB2DBDFT=ODLAHD01

function getAgNID() {
	AGID_NAME=$1
	COLLECTION=$2
	db2 -xt "select trim(ag.name)||','||n.nid from arsag ag	inner join arsnode n on ag.sid = n.sid and n.name='$COLLECTION' where ag.agid_name='$AGID_NAME'"
}

function fetchObject() {
	vTOBJ=$1
	COLLECTION=$2
	readarray -d'.' -t obj <<<$vTOBJ
	AGID_NAME=${obj[0]}
	DOC_NAME=$(tr -d 'L' <<<${obj[1]})$(echo -n ${obj[2]})
	for r in $(getAgNID $AGID_NAME $COLLECTION) ; do
		readarray -d',' -t obj <<<$r
		arsadmin retrieve -I $DB2DBDFT -u admin -g ${obj[0]} -n $(tr -d [:blank:] <<<${obj[1]})-0 $DOC_NAME
		[ $? -eq 0 ] && break
	done
	[ $? -ne 0 ] && echo "ERROR: while retrieving $vTOBJ" && return 1
	echo $DOC_NAME
}
[ $# -ne 2 ] && echo "Usage: $0 tapeDir Collection" >&2 && exit 1
TD=$1
COLLECTION=$2
[ ! -d $TD ] && echo "ERROR: Tape directory not found: $TD" >&2 && exit 2

# Connect to DB2
db2 -o- connect to $DB2DBDFT
trap 'db2 -o- terminate' exit

for o in ${TD}/*.*.* ; do
	echo -n "$o: "
	doc_name=$(fetchObject $(basename $o) $COLLECTION)
	[ $? -eq 0 ] && sha1sum $o $doc_name|perl -lane '{push @a,$F[0]}END{print(($a[0] eq $a[1])?"OK":"FAILED");exit (($a[0] eq $a[1])?0:1)}' && rm -f $doc_name
done 