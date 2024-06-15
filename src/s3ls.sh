#!/usr/bin/bash
function s3ls {
p1=$1
dt=$(date -uR)
/opt/freeware/bin/curl -skIX GET https://$S3BUCKET.ds71s3-scs.tauri.ch/IBM/ONDEMAND/$p1 -H "Date: $dt" -H "Authorization: AWS $S3OWNER:$(echo -en "GET\n\n\n$dt\n/$S3BUCKET/IBM/ONDEMAND/$p1" | openssl dgst -sha1 -mac HMAC -macopt key:$S3KEY -binary | /opt/freeware/bin/base64)" >$TMPD/s3ls.dat
if [ $(grep -c ^ETag $TMPD/s3ls.dat) -eq 0 ] ; then
        echo "$p1 not found on S3"  >&2
#       cat $TMPD/s3ls.dat >&2
fi
cat $TMPD/s3ls.dat
}

[ $# -ne 1 ] && echo -e "Usage: $0 PathObject\ne.e.: s3ls.sh ARCHIVE/XEA/123FAA/123FAA1" >&2 && exit 1
TMPD=$(mktemp -d)
S3BUCKET=p-ondemand
S3OWNER=blkb-p-ondemand
S3KEY=xxxxxxxxxxxxx
trap 'rm -rf $TMPD' exit
s3ls $1
