#!/usr/bin/bash
[ $# -eq 0 ] && echo "Usage: $(basename $0) AGN|stop|-nth N" >&2 && exit 1
AGN=$1
NTH=2
ROOT=DATA/S3
STOP=$(basename $0 .sh).stop
NTHF=$(basename $0 .sh).nth

if [ "$AGN" == "stop" ] ; then
	touch $STOP
	echo "WARN: $(date '+%F %T') -- Stop requested"
	exit
elif [ "$AGN"  == "-nth" ] ; then
  echo $2 >$NTHF
	echo "WARN: $(date '+%F %T') -- Requested to change number of processes to $2"
  exit
fi

echo "INFO: $(date '+%F %T') Started import of $AGN with $NTH threads. PID=$$"

for d in $(find $ROOT/$AGN/* -prune -type d | sort -k1.4n) ; do
  # Check if stop was requested
  if [ -f $STOP ] ; then
    sms2nn "import of $AGN stopped"
    rm $STOP
    break
  fi
  
  # Check 
  echo -n "INFO: $(date '+%F %T') -- Loading $ROOT/$AGN/$d ... "
  # $ROOT/MFA/SUB1/19453FAA/19453FAAA
  aws s3 cp $d/ s3://p-ondemand/IBM/ONDEMAND/AGARCH/$AGN/ --no-guess-mime-type --only-show-errors --recursive >>$AGN.import.log 2>&1 &
  echo $!
  sleep 1
  
  # Check if process change was requested
  if [ -f $NTHF ] ; then
    NTH=$(cat $NTHF)
    echo "WARN: $(date '+%F %T') -- Number of processes changed to $NTH"
    rm $NTHF
  fi

  while [ $(jobs -p|wc -l) -ge $NTH ] ; do
    # Number of processes reached, wait for any child to finish
    wait -n
  done
done

# no stopping nor processes change from here
rm -f $STOP $NTHF

echo "INFO: $(date '+%F %T') $AGN final wait ..."
wait

# done
sms2nn "Import of $AGN finished"
echo "INFO: $(date '+%F %T') -- Finished importing $AGN"
