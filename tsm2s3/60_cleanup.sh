#!/usr/bin/bash
[ $# -ne 1 ] && echo "Usage: $0 AGID_NAME" >&2 && exit 1
AGN=$1

find DATA/DOC/${AGN} -type f 2>/dev/null | xargs rm -f &
sleep 1
find DATA/S3/${AGN} -type f 2>/dev/null | xargs rm -f &
sleep 2
[ $(jobs -p|wc -l) -gt 0 ] && wait

rm -rf DATA/S3/${AGN} DATA/DOC/${AGN}
yes n | gzip DATA/LOG/${AGN}*
sync
df -m DATA/



