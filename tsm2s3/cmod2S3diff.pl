#!/usr/bin/bash -x
[ $# -lt 1 ] && echo "Usage: $(basename $0) all|\"arsag where clause\"" >&2 && exit 1

if [ "$(echo $1|tr [:upper:] [:lower:])" != "all" ] ; then
ARSAGWHERE="$1 and"
else
unset ARSAGWHERE
fi

NTHREADS=16
export INSTANCE=$(echo ${INSTANCE:-$DB2INSTANCE}|tr [:lower:] [:upper:])
export S3PROFILE="entris-p-ondemand"
echo "INFO: $(basename $0) Started at $(date)"
export SERVICE=$(db2 get dbm cfg | perl -lne 'print $1 if /\(SVCENAME\)\s+=\s+(\S+)/')
export TS=$(date +%Y%m%d%H%M)
db2 connect to $INSTANCE
AGNS=${INSTANCE}.agns
db2 -t "export to $AGNS of DEL modified by nochardel select upper(agid_name),load_id from arsag where $ARSAGWHERE name not like 'System%' and sid in (select sid from arsnode where bitand(status,524288)>0);"
db2 terminate

[ ! -f $AGNS ] && echo "ERROR: Unable to get list AG names from $INSTANCE" >&2 && exit 2
trap 'rm -f $AGNS' exit

DATA=${DATA:-/ars/ent/data/S3}/$$
[ ! -d $DATA/data ] && mkdir -p $DATA/data
[ ! -d $DATA/log ] && mkdir -p $DATA/log

function loadAwsls() {
AGN=$1
FIFO=$DATA/data/${AGN}.dat
LOG=$DATA/log/${AGN}.log
TKN=$DATA/log/${AGN}.tkn
touch $TKN
trap 'rm -f $TKN' return
#
# DDL for NN_AWSLS:
# create table NN_AWSLS (AGID_NAME char(3) not null, DOC_NAME varchar(11) not null);
#

#trap 'rm -f $FIFO' exit
echo "INFO: $(basename $0) $AGN Started on $(date)" >$LOG
echo aws s3api list-objects-v2 --prefix IBM/ONDEMAND/$INSTANCE/$AGN --bucket p-ondemand --profile $S3PROFILE >>$LOG
aws s3api list-objects-v2 --prefix IBM/ONDEMAND/$INSTANCE/$AGN --bucket p-ondemand --profile $S3PROFILE >$FIFO 2>>$LOG
perl -lane 'next unless /^CONTENTS/;$a=join(",",(split(/\//,$F[2]))[3,5]);print $a unless $a =~ /A1$/' ${FIFO} >${FIFO}.del 2>>$LOG
gzip $LOG &
}


# while read csv ; do
	# agn=$(echo $csv|cut -f1 -d',')
	# echo "INFO: Exporting $agn ..."
	# loadAwsls $agn &
	# sleep 1
	# if [ $(ls -1 $DATA/log/*.tkn|wc -l) -ge $NTHREADS ] ; then
		# echo "INFO: waiting ..."
		# wait -n
	# fi
# done <$AGNS
# echo "INFO: All AGNs have been quequed, waiting to complete ..."
# wait

# echo "INFO: Loading AWS S3 data to NN_AWSLS table ..."
# FIFO=$DATA/fifo
# mkfifo $FIFO
# cat $DATA/data/*.del >>$FIFO &
# sleep 1
# db2 connect to $INSTANCE
# db2 -t "load from $FIFO of DEL replace into NN_AWSLS NONRECOVERABLE;"
# db2 terminate
# rm -f $FIFO 
# #rm -rf $DATA/data $DATA/log &

# echo "INFO: Updating stats for NN_AWSLS table ..."
# update_stats.sh NN_AWSLS

echo "INFO: Sterted to scan table segments ..."
/ars/odadm/bin/perl -wx $0 $AGNS "$ARSAGWHERE"
echo "INFO: $(basename $0) Finished at $(date)"

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
my $outputMissing = 'cmod2S3diff.'.$ENV{TS}.'.csv';
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
print $fh 'The storage compare between CMOD ',$ENV{INSTANCE},' instance and ECS S3 started on ',scalar(localtime(time)),"\n";
print $fh "=====================================================================================================\n";
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
			my $c=-1;
			my ($agName) = @{$dh->selectcol_arrayref(qq/select name from arsag where agid_name=?/,undef,$agid_name)};
			open(my $fh,'>>',$outputMissing) || die "ERROR: Unable to open $outputMissing\n$!\n";
			print $fh "\n$agName:$segment\n============================================================\n";
			my $csv = Text::CSV->new({binary => 1,eol => "\n", undef_str => "\\N" });
			while (my $res = $sh->fetch) {
				my ($table_name, $doc_name) = @$res;
				unless (s3ls($agid_name,$doc_name)) {
					$csv->print($fh,$res);
					++$c;
				}
			}
			print $fh "$c error(s) found.\n";
			close($fh);
			print "DEBUG: segment=$segment\trows=$c\n" if ($debug);
		}
		$sh->finish;
	} # dequeue()
	$dh->disconnect;
}

sub s3ls {
	my ($agid_name,$doc_name);
	my $dir = 'RES';
	$dir = $1 if ($doc_name =~ /^(\d+\D{3})/);
	my $object = join('/','s3:/','p-ondemand','IBM','ONDEMAND',$ENV{INSTANCE},$agid_name,$dir,$doc_name);
	return grep {/^$doc_name$/} map {chomp;(split(/\s+/))[-1]} (qx/aws s3 ls $object --profile $ENV{S3PROFILE} 2>\/dev\/null/);
}
