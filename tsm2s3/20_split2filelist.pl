#!/ars/odadm/bin/perl -w
use DBI;
use strict;

die "Usage: $0 AGID_NAME\n" unless (scalar(@ARGV));
my $AGID_NAME=shift;

my $MAXREC=1500;
my $BASEDIR='DATA/DOC';
my $DBUSER='odadm';
my $DBPASSWD='adm4archive';
my $TCPPORT='db2c_agarch';
my $DBCONNECT='DATABASE='.$ENV{DB2INSTANCE}.'; HOSTNAME=localhost; PORT='.$TCPPORT.'; PROTOCOL=TCPIP';

my $dh = DBI->connect('dbi:DB2:'.$DBCONNECT,$DBUSER,$DBPASSWD,{PrintError => 0, RaiseError => 1, ShowErrorStatement => 1, AutoCommit => 1, FetchHashKeyName => 'NAME_lc'});

# Prepare select
my $sel = $dh->prepare(qq/
select node,'\/AGARCH\/$AGID_NAME\/'||decode(type,'R','RES','DOC')||'\/'||name from SC_$AGID_NAME where status=0 order by node
/);

# Execute
$sel->execute();

my $fh; # Current file handle
my $rc = $MAXREC; # record counter
my $fc = 0; # File counter
my $prev_node = '';  # previous node (qry should be ordered)
my $is_open = 0; # open filehandle flag

while (my $r = $sel->fetch) {
  my ($node,$doc)=@$r;
  
  # close ouput, if new node or MAXREC
  if (!(--$rc) || ($node ne $prev_node)) {
    warn "DEBUG: rc=$rc\tnode=$node\tprev_node=",(defined($prev_node)?$prev_node:'undef'),"\n" if ($ENV{DEBUG});
    close($fh) if (defined($fh));
    $is_open = 0;
  }
  
  # Open output, if not already open
  unless ($is_open) {
    # LST file name: ABA00001.agkb_11y.lst
    my $fn = join('.',$AGID_NAME.sprintf("%05d",++$fc),$node,'lst');
    my $log = $fn;
    $log =~ s/lst$/log/;
    open($fh,'>',$fn)||die "ERROR:$fn $!";
    # Reset counters
    $is_open = 1;
    $rc = $MAXREC;
    # print the export command
    my $expDir = "$BASEDIR/$AGID_NAME";
#    mkdir $expDir unless (-d $expDir);
#    print 'yes 4 2>/dev/null|',"$node ret -replace=no -filelist=$fn $expDir/ >$log 2>&1\n";
  }
  
  # write record to list file
  print $fh $doc,"\n";
  $prev_node = $node;
}
close($fh) if ($is_open);

################## END ##################
__END__
my $fh;
my $fileList;
my $fn=0;
my $lc=0;
my $PAGN='';
my $node='';
my $AGID_NAME = shift;
$|=1;


# Create queues
my $q = Thread::Queue->new();

# Start workers
threads->create(\&execExport) for (1..8);
sleep 1;

# Info the PID
warn "INFO: PID=$$\n";

my @nodes = @{$dh->selectcol_arrayref(qq/select distinct node from SC_$AGID_NAME where status=0/)};
warn 'DEBUG: Nodes=(',join(', ',@nodes),")\n" if ($ENV{DEBUG});

for my $n (@nodes) {
  $sel->execute($n);
  my $rc=0;
  $lc=0;
  $PAGN='';
  $node='';
  while (my $l=$sel->fetch) {
    #
    # agkb_02y,/AGARCH/WBA/DOC/2FAA1
    # agkb_02y,/AGARCH/WBA/DOC/2FAAA
    # agkb_02y,/AGARCH/WBA/RES/2
    #
    ($node,$l) = @$l;
    my ($AGN,$OBJ) = (split(/\//,$l))[2,4];
    next if (-f $BASEDIR.join('/',($AGN,$OBJ)));	# Skip existing
    if (!defined($fh) || ($AGN ne $PAGN) || !(--$lc)) {
      doClose();
      $fileList = $AGN.sprintf("%05d",++$fn).'.'.$node.'.lst';
      warn "DEBUG: Openning $fileList\n" if ($ENV{DEBUG});
      open($fh,'>',$fileList) || die "ERROR: $!\n";
      $PAGN = $AGN;
      $lc=$MAXLINES;
    }
    $rc++;
    warn "DEBUG: line $rc\tAGN=$AGN\tPAGN=$PAGN\n" if ($ENV{DEBUG});
    print $fh $l,"\n";
  }
  doClose();
}
warn "DEBUG: Final close\n" if ($ENV{DEBUG});

# Finale close
doClose();
#close($fi);
$dh->disconnect;

# Enqueue the end
$q->end();

END {
    if (defined($q)) {
		# Close the queues
		$q->end();

		# Wait until all finished.
		$_->join() for threads->list();
	}
	unlink '20_split2filelist.stop' if (-f '20_split2filelist.stop');
}
#
# End
#

sub doClose {
	if (defined($fh)) {
		close($fh);
		warn "DEBUG: Closing $fileList\n" if ($ENV{DEBUG});
		my $expDir = "$BASEDIR/$PAGN/";
		mkdir $expDir unless (-d $expDir);
		warn "DEBUG: $node ret -replace=no -filelist=$fileList $expDir\n" if ($ENV{DEBUG});
		$q->enqueue("$node ret -replace=no -filelist=$fileList $expDir");
	}
} # doClose()

sub execExport {
	while (defined(my $cmd = $q->dequeue())) {
		my $logFile = $cmd;
		$logFile =~ s/^.+?=(\S+?)lst/$1log/;
		my $batch = $logFile;
		$logFile .= '.log';
		$cmd .= " >$logFile 2>&1";
		$cmd = 'yes 4 2>/dev/null|'.$cmd;
		warn "INFO: $cmd\n";
		# my $rc = system($cmd);
		# warn "WARNING: $batch RC=$rc\n" if ($rc);
		last if (-f '20_split2filelist.stop');
	}
} # execExport()
