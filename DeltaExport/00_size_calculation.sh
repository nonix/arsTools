#!/usr/bin/env bash

. ${0%/*}/config.ini

AGIDNAME="$1"
if [[ -z "${AGIDNAME}" ]]; then
  echo "Usage: $0 <AGID_NAME>"
  exit
fi

function finished {
  db2 +o connect reset
  db2 +o terminate
  exit
}

db2 +o -x "connect to ${DB2_INSTANCE} user ${DB2_USER} using ${DB2_PWD}"
AGID=$(db2 -x "select agid from arsag where agid_name=upper('${AGIDNAME}')")
if [[ -s "${AGID}" ]]; then
  echo "ERROR: ${AGIDNAME} not found";
  finished
fi

TABLENAME=$(db2 -x "select table_name from arsseg where agid=${AGID} order by int(substr(table_name,4))")

echo "${AGIDNAME}"
TOT_OBJ=0
TOT_DOCS=0
TOT_DOCS2=0
TOT_SUM_CACHE=0
TOT_SUM_DOCS=0
for seg in ${TABLENAME}; do
  echo -e "\t${seg}"
  SUM_COMP=$(db2 -x "select sum(cast(comp_len as bigint))                                     from (select distinct doc_name,                   comp_off, comp_len from ${seg})")
  SUM_DOCS=$(db2 -x "select sum(cast(doc_len  as bigint)), count(distinct doc_name), count(*) from (select distinct doc_name, doc_off, doc_len, comp_off, comp_len from ${seg})")
  NB_OBJS=$(echo "${SUM_DOCS}"  | awk '{print $2}')
  NB_DOCS=$(echo "${SUM_DOCS}"  | awk '{print $3}')
  NB_DOCS2=$(db2 -x "select count(*) from ${seg}")
  SUM_DOCS=$(echo "${SUM_DOCS}" | awk '{print $1}')
  ((TOT_OBJ+=NB_OBJS))
  ((TOT_DOCS+=NB_DOCS))
  ((TOT_DOCS2+=NB_DOCS2))
  ((TOT_SUM_DOCS+=SUM_DOCS))
  ((TOT_SUM_CACHE+=SUM_COMP))
  echo -e "\t\tSize Cache:\t$((SUM_COMP)) bytes - "$(echo -e "scale=2\n${SUM_COMP}/1024/1024/1024" | bc)" GiB"
  echo -e "\t\tSize Docs:\t$((SUM_DOCS)) bytes - "$(echo  -e "scale=2\n${SUM_DOCS}/1024/1024/1024" | bc)" GiB"
  echo -e "\t\tDB Docs (uniq):\t$((NB_DOCS))"
  echo -e "\t\tDB Docs:\t$((NB_DOCS2))"
  echo -e "\t\tDB Objects:\t$((NB_OBJS))"
done

echo
echo -e "\tTot Cache Size:\t${TOT_SUM_CACHE} bytes - "$(echo -e "scale=2\n${TOT_SUM_CACHE}/1024/1024/1024" | bc)" GiB"
echo -e "\tTot Docs Size:\t${TOT_SUM_DOCS} bytes - "$(echo   -e "scale=2\n${TOT_SUM_DOCS}/1024/1024/1024"  | bc)" GiB"
echo -e "\tTot Docs Count (uniq):\t${TOT_DOCS}"
echo -e "\tTot Docs Count:\t${TOT_DOCS2}"
echo -e "\tTot Objs Count:\t${TOT_OBJ}"
echo

if [[ -d "${CMOD_CACHE}/0/${AGIDNAME}/DOC" ]]; then
  NB_OBJS_CACHE=$(find "${CMOD_CACHE}/0/${AGIDNAME}/DOC" -type f | grep -v '1$' | wc -l)
  echo -e "\tCache Obj:\t$((NB_OBJS_CACHE))"
fi

if [[ -d "${CMOD_CACHE}/retr/${AGIDNAME}/DOC" ]]; then
  NB_LINKS_CACHE=$(find "${CMOD_CACHE}/retr/${AGIDNAME}/DOC" -type l | grep -v '1$' | wc -l)
  echo -e "\tCache Links:\t$((NB_LINKS_CACHE))"
fi

if [[ -f "${CMOD_REMOTE}/${AGIDNAME}.manifest" ]]; then
  NBDOCMANIFEST=$(sed 's/,//g' "${CMOD_REMOTE}/${AGIDNAME}.manifest" |awk '/Document count/ {TOTAL=TOTAL+$NF}END{print TOTAL}')
  echo -e "\tManifest Docs:\t$((NBDOCMANIFEST))"
fi

finished
