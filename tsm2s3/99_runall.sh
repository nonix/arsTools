#!/usr/bin/bash
[ $# -ne 1 ] && echo "Usage: $0 AGID_NAME" >&2 && exit 1
AGN=$1

./14_db2exec.sh DATA/SQL/SC_${AGN}.sql

db2 -o- connect to AGARCH
typeset -i rows=$(db2 -xnt "select count(*) from SC_${AGN} where status=0;")
db2 -o- terminate
if [ $rows -eq 0 ] ; then
  echo "INFO: Nothing to do for ${AGN}"
  ./60_cleanup.sh  ${AGN}
  exit 0
fi

echo "INFO: *** $rows container(s) to transfer"

# Extract doc_name(s) from TSM to staging area
#   i.e.: ./20_split2filelist.pl CKA
./20_split2filelist.pl $AGN

# Check Errors; where RC=3072
perl -lne "next unless (/^ANS1345E/);print unless (/1\'$/)" ${AGN}*.log

# Update status to "exported" in SC_AGID_NAME
#   i.e.: ls -1 DATA/DOC/CKA/ | ./updateSC.pl CKA 1
ls -1 DATA/DOC/${AGN}/ | ./updateSC.pl ${AGN} 1

# Create S3 links
#   i.e.: find DATA/DOC/CKA -type f |sort -t'/' -k4,4n|./25_link4s3.pl CKA
find DATA/DOC/${AGN} -type f |sort -t'/' -k4,4n|./25_link4s3.pl ${AGN}

# Sync local S3 dirs to S3 storage
#   i.e.: ./30_awssync.sh CKA
./30_awssync.sh ${AGN}

# Update status to "uploaded" in SC_AGID_NAME
#   i.e.: aws s3 ls s3://t-ondemand/IBM/ONDEMAND/AGARCH/CKA/ --recursive | perl -F/ -lane 'print $F[-1]'|./updateSC.pl CKA 2
aws s3 ls s3://t-ondemand/IBM/ONDEMAND/AGARCH/${AGN}/ --recursive | perl -F/ -lane 'print $F[-1]'|./updateSC.pl ${AGN} 2

# Check where missing
db2 -o- connect to AGARCH
db2 -t "select name,status from SC_${AGN} where status<2;"
db2 -o- terminate

# Re-map nid to S3
#   i.e.: ./40_remapnid.pl CKA
./40_remapnid.pl ${AGN}

# Check failed / missing
db2 -o- connect to AGARCH
db2 -t "select name,status from SC_${AGN} where status<3;"
db2 -o- terminate

# Clean-up storage
./60_cleanup.sh  ${AGN}
