#!/usr/bin/bash
export DB2DBDFT=ODLAHD01

function getAgNID() {
	AGID_NAME=$1
	db2 -o- connect to $DB2DBDFT
	db2 -xt "select trim(ag.name)||','||n.nid from arsag ag	inner join arsnode n on ag.sid = n.sid where ag.agid_name='$AGID_NAME'"
	trap 'db2 -o- terminate' exit
}

function fetchObject() {
	vTOBJ=$1
	readarray -d'.' -t obj <<<$vTOBJ
	AGID_NAME=${obj[0]}
	DOC_NAME=$(tr -d 'L' <<<${obj[1]})$(echo -n ${obj[2]})
	for r in $(getAgNID $AGID_NAME) ; do
		readarray -d',' -t obj <<<$r
		arsadmin retrieve -I $DB2DBDFT -u admin -g ${obj[0]} -n $(tr -d [:blank:] <<<${obj[1]})-0 $DOC_NAME
		[ $? -eq 0 ] && break
	done
	[ $? -ne 0 ] && echo "ERROR: while retrieving $vTOBJ" && return 1
	echo $DOC_NAME
}

for o in ../DIRA/*.*.* ; do
	echo -n "$o: "
	doc_name=$(fetchObject $(basename $o))
	[ $? -eq 0 ] && sha1sum $o $doc_name|perl -lane '{push @a,$F[0]}END{print(($a[0] eq $a[1])?"OK":"FAILED");exit (($a[0] eq $a[1])?0:1)}' && rm -f $doc_name
done 