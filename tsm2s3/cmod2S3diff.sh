#!/usr/bin/bash
[ $# -lt 2 ] && echo "Usage: $(basename $0) report_name all|\"arsag where clause\"" >&2 && exit 1

export OUTRPT=$1

if [ "$(echo $2|tr [:upper:] [:lower:])" != "all" ] ; then
ARSAGWHERE="$2 and"
else
unset ARSAGWHERE
fi

HRTS=$(/opt/freeware/bin/date)
export TS=$(/opt/freeware/bin/date --date="$HRTS" +%Y%m%d%H%M)

#exec > $(basename $0 .sh).${TS}.log
#exec 2>&1

DOCLEAN=1		# Set to 0 to NOT to remove data, log, AGNS
NTHREADS=16
export INSTANCE=$(echo ${INSTANCE:-$DB2INSTANCE}|tr [:lower:] [:upper:])
export S3PROFILE="entris-p-ondemand"
echo "INFO: $(basename $0) Started at $HRTS"
export SERVICE=$(db2 get dbm cfg | perl -lne 'print $1 if /\(SVCENAME\)\s+=\s+(\S+)/')
db2 connect to $INSTANCE
AGNS=${INSTANCE}.agns
db2 -t "export to $AGNS of DEL modified by nochardel select upper(agid_name),load_id from arsag 
		where $ARSAGWHERE name not like 'System%' and sid in (select sid from arsnode where bitand(status,524288)>0)
		and agid in (select distinct agid from arsseg);"
db2 terminate

[ ! -f $AGNS ] && echo "ERROR: Unable to get list AG names from $INSTANCE" >&2 && exit 2

DATA=${DATA:-/ars/ent/data/S3}/$$
[ ! -d $DATA/data ] && mkdir -p $DATA/data
[ ! -d $DATA/log ] && mkdir -p $DATA/log

[ $DOCLEAN -gt 0 ] && trap 'rm -rf $AGNS $DATA' exit

function loadAwsls() {
AGN=$1
TKN=$DATA/log/${AGN}.tkn
touch $TKN
trap 'rm -f $TKN' return

FIFO=$DATA/data/${AGN}.dat
LOG=$DATA/log/${AGN}.log
#
# DDL for NN_AWSLS:
# create table NN_AWSLS (AGID_NAME char(3) not null, DOC_NAME varchar(11) not null);
#

#trap 'rm -f $FIFO' exit
echo "INFO: $(basename $0) $AGN Started on $(date)" >$LOG
echo aws s3api list-objects-v2 --prefix IBM/ONDEMAND/$INSTANCE/$AGN --bucket p-ondemand --profile $S3PROFILE >>$LOG
aws s3api list-objects-v2 --prefix IBM/ONDEMAND/$INSTANCE/$AGN --bucket p-ondemand --profile $S3PROFILE >$FIFO 2>>$LOG
RC=$?
[ $RC -ne 0 ] && echo "WARNING: s3api $AGN exit code: $RC" >> $LOG
perl -lane 'next unless /^CONTENTS/;$a=join(",",(split(/\//,$F[2]))[3,5]);print $a unless $a =~ /A1$/' ${FIFO} >${FIFO}.del 2>>$LOG
gzip $LOG &
}

while read csv ; do
	agn=$(echo $csv|cut -f1 -d',')
	echo "INFO: Exporting $agn ..."
	loadAwsls $agn &
	sleep 2 && sync
	while [ $(ps -fu $USER | grep -cw [a]ws) -ge $NTHREADS ] ; do
		echo "INFO: waiting ..."
		wait -n
	done
done <$AGNS
echo "INFO: All AGNs have been quequed, waiting to complete ..."
wait

echo "INFO: Loading AWS S3 data to NN_AWSLS table ..."
FIFO=$DATA/fifo
mkfifo $FIFO
cat $DATA/data/*.del >>$FIFO &
sleep 1
db2 connect to $INSTANCE
db2 -o- -t "load from $FIFO of DEL replace into NN_AWSLS NONRECOVERABLE;"
db2 terminate
rm -f $FIFO 
#rm -rf $DATA/data $DATA/log &

echo "INFO: Updating stats for NN_AWSLS table ..."
update_stats.sh NN_AWSLS && rm -f update_stats.log

echo "INFO: Sterted to scan table segments ..."
TMPRPT=$(basename $0 .sh).${TS}.csv


# Call embedded perl processor
/ars/odadm/bin/perl -wx $0 "$TMPRPT" "$AGNS" "$ARSAGWHERE"

# Final report post processing
echo "The storage compare report between CMOD $INSTANCE instance and ECS S3 as of $HRTS" > $OUTRPT
[ ! -z "$ARSAGWHERE" ] && echo "ARSAG WHERE $ARSAGWHERE ..." >> $OUTRPT
echo '******************************* ERROR(s) FOUND **********************************************' >> $OUTRPT
perl -lne 'unless (/(^\d+) error/) {push @a,$_ ;next};push @a,$_;print join("\n",@a) if ($1);@a=()' $TMPRPT >> $OUTRPT
echo '******************************* FULL REPORT ***********************************************' >> $OUTRPT
cat $TMPRPT >> $OUTRPT && rm -f $TMPRPT
echo "INFO: $(basename $0) Finished at $(date)"

# The end of the script
exit

#!/ars/odadm/bin/perl -w
use threads;
use threads::shared;
use Thread::Queue;
use Text::CSV qw( csv );
use POSIX qw( strftime );
use DBI;

my $NTHREADS=6;
my $DBUSER='odadm';
my $DBPASSWD='1qay.2wsx';
my $DBCONNECT='DATABASE='.$ENV{INSTANCE}.'; HOSTNAME=localhost; PORT='.$ENV{SERVICE}.'; PROTOCOL=TCPIP';
my $debug = defined($ENV{DEBUG})?$ENV{DEBUG}:0;

my $ulock :shared;
my $outputMissing = shift;
my $lastLID = csv(in => $ARGV[0],headers => [qw( agid_name load_id )],key => "agid_name", value => "load_id", binary => 1) || die "ERROR: Unable to parse AGNS\n";
my $arsagWhere = ' 1=1 ';
if (defined($ARGV[1]) && $ARGV[1] =~ /and/) {
	$arsagWhere = $ARGV[1];
	$arsagWhere =~ s/\s+and$//;
}
# Create queues
my $q = Thread::Queue->new();

# Start workers
threads->create(\&scanSegment) for (1..$NTHREADS);
sleep 1;

# Connect to DB2
$dh = DBI->connect('dbi:DB2:'.$DBCONNECT,$DBUSER,$DBPASSWD,{PrintError => 0, RaiseError => 1, ShowErrorStatement => 1, AutoCommit => 1, FetchHashKeyName => 'NAME_lc'});
my %segments = @{$dh->selectcol_arrayref(qq/select upper(ag.agid_name), seg.table_name from arsag ag inner join arsseg seg on seg.agid=ag.agid where ag.name not like 'System%' and ag.agid in (select agid from arsag where $arsagWhere)/,{Columns=>[2,1]})};
open(my $fh,'>',$outputMissing) || die "ERROR: Unable to open $outputMissing\n$!\n";
close($fh);

$dh->disconnect;

# Enqueu all segments
for (sort(keys(%segments))) {
	print 'DEBUG: enqueue=',join(':',($segments{$_},$_)),"\n"  if ($debug);
	$q->enqueue(join(':',($segments{$_},$_,$lastLID->{$segments{$_}})));
}

END {
    if (defined($q)) {
		# Close the queues
		$q->end();

		# Wait until all finished.
		$_->join() for threads->list();
		
		open(my $fh,'>>',$outputMissing) || die "ERROR: Unable to open $outputMissing\n$!\n";
		print $fh "\nThe storage compare finished at ",scalar(localtime(time)),"\n";
		close($fh);
    }
}

sub scanSegment {
	$|=1;
	my $dh = DBI->connect('dbi:DB2:'.$DBCONNECT,$DBUSER,$DBPASSWD,{PrintError => 0, RaiseError => 1, ShowErrorStatement => 1, AutoCommit => 1, FetchHashKeyName => 'NAME_lc'});

	while (my $item = $q->dequeue) {
		print "DEBUG: de-queue item=$item\n" if ($debug); 
		my ($agid_name,$segment,$load_id) = split(/:/,$item);
		print "DEBUG: agid_name=$agid_name, segment=$segment\n" if ($debug); 
		my $sql = qq/
			select '$segment' as table_name, t.doc_name from 
			( select distinct translate(doc_name,'','\$','') as doc_name from $segment where pri_nid > 1 and int(left(doc_name,locate(trim(translate(doc_name,'','0123456789','')),doc_name)-1)) < ?
			union
			select distinct cast(resource as varchar(11)) as doc_name from $segment where resource > 0 and pri_nid > 1 and int(left(doc_name,locate(trim(translate(doc_name,'','0123456789','')),doc_name)-1)) < ? ) t
			left outer join NN_AWSLS n
				on t.doc_name = n.doc_name
				  and n.agid_name=?
			where n.doc_name is null for read only with ur
		/;
		print "DEBUG: SQL=$sql\n" if ($debug);
		my $sh = $dh->prepare ($sql);
		$sh->execute($load_id,$load_id,$agid_name);
		{
			lock($ulock);
			my $c=0;
			my ($agName) = @{$dh->selectcol_arrayref(qq/select name from arsag where agid_name=?/,undef,$agid_name)};
			open(my $fh,'>>',$outputMissing) || die "ERROR: Unable to open $outputMissing\n$!\n";
			print $fh "\n$agName:$segment\n============================================================\n";
			my $csv = Text::CSV->new({binary => 1,eol => "\n", undef_str => "\\N" });
			while (my $res = $sh->fetch) {
				my ($table_name, $doc_name) = @$res;
				# Workaround for faulty S3 (aws cli?) re-scan the missing again ...
				unless (s3ls($dh,$agid_name,$doc_name)) {
					$csv->print($fh,$res);
					++$c;
				}
			}
			$sh->finish;
			print $fh "$c error(s) found.\n";
			close($fh);
			print "DEBUG: segment=$segment\trows=$c\n" if ($debug);
		}
		$sh->finish;
	} # dequeue()
	$dh->disconnect;
}

sub s3ls {
	my ($dh,$agid_name,$doc_name) = @_;
	my $dir = 'RES';
	$dir = $1 if ($doc_name =~ /^(\d+\D{3})/);
	my $object = join('/','s3:/','p-ondemand','IBM','ONDEMAND',$ENV{INSTANCE},$agid_name,$dir,$doc_name);
	print "WARNING: re-scan $object\n";
	my $retval = '';
	for my $dn (grep {/^$doc_name$/} map {chomp;(split(/\s+/))[-1]} (qx/aws s3 ls $object --profile $ENV{S3PROFILE} 2>\/dev\/null/)) {
		# Re-insert the missings, this is for consintancy only
		$dh->do(qq/MERGE INTO NN_AWSLS n
					 USING (SELECT ? as agid_name,? as doc_name FROM sysibm.sysdummy1) t
					 ON (n.agid_name = t.agid_name and n.doc_name = t.doc_name)
					WHEN NOT MATCHED THEN
					  INSERT
					  (agid_name, doc_name)
					  VALUES (t.agid_name, t.doc_name)
				/,undef,$agid_name,$doc_name);
		$retval = $dn;
	}
	return $retval;
}
