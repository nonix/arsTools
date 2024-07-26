#!/usr/bin/bash
[ $# -lt 2 ] && echo "Usage: $0 doc_name [x]comp_off [[x]comp_len" >&2 && exit 1
doc_name=$1
comp_off=$(echo $2| tr -d ' ')
comp_len=$(echo $3|tr -d ' ')
[ "$(echo $comp_off|cut -c1)" == "x" ] && comp_off=$((16#$(echo $comp_off|cut -c2-)))

# Check if comp_len is provided
if [ ! -z "$comp_len" ] ; then
 [ "$(echo $comp_len|cut -c1)" == "x" ] && comp_len=$((16#$(echo $comp_len|cut -c2-)))
 next_off=$(($comp_off+$comp_len)) 
 l="-l $comp_len"
fi

OUT=${doc_name}.$comp_off.lo
echo arsadmin decompress -s $doc_name -b $comp_off $l -o $OUT
arsadmin decompress -s $doc_name -b $comp_off $l -o $OUT
[ $? -eq 0 ] && [ -f $OUT ] && echo $OUT
[ ! -z "$l" ] && echo Next:$next_off