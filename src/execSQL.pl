#!/ars/odadm/bin/perl -w
use 5.012;
use POSIX qw/strftime/;
use threads qw(yield);
use threads::shared;
use Thread::Queue;
use IO::File;
use Text::CSV qw( csv );
use DBI;
use Fcntl qw(:flock);
use strict;


#
# Main()
#

die "Usage: $0 input.sql output.csv\nEnv:\nDBIPASSWD, DBIUSER, DBICONNECTION\nExample: dbi:DB2:DATABASE=$ENV{DB2INSTANCE}; HOSTNAME=localhost; PORT=db2c_$ENV{DB2INSTANCE}; PROTOCOL=TCPIP\n" unless (scalar(@ARGV) == 2);

my $outFile = $ARGV[1];
# Delete the outFile if exists
unlink $outFile if (-f $outFile);

# Create queues
my $q = Thread::Queue->new();

# Start workers
threads->create(\&execSQL) for (1..8);
sleep 1;

# Enqueue SQLs
my $fi;
if ($ARGV[0] eq '-') {
    $fi = \*STDIN;
} else {
    open($fi,'<',$ARGV[0]) || die "ERROR: $!\n";
}

while (<$fi>){
	chomp;
	# Remove command separator ";"
	s/;\s*$//;
    # next if comment
    next if (/^--/);
	# Enqueue or skip empty line
	$q->enqueue($_) unless (/^\s*$/);
}

# Enqueue the end
$q->end();

close($fi);


END {
    if (defined($q)) {
		# Close the queues
		$q->end();

		# Wait until all finished.
		$_->join() for threads->list();
	}
}
#
# End
#

sub execSQL {
	my $dh;
	if (defined($ENV{DBICONNECTION}) && defined($ENV{DBIUSER}) && defined($ENV{DBIPASSWD})) {
		$dh = DBI->connect($ENV{DBICONNECTION},$ENV{DBIUSER},$ENV{DBIPASSWD},{PrintError => 0, RaiseError => 1, ShowErrorStatement => 1, AutoCommit => 1, FetchHashKeyName => 'NAME_lc'});
	} else {
		$dh = DBI->connect("dbi:DB2:DATABASE=$ENV{DB2INSTANCE}; HOSTNAME=localhost; PORT=db2c_$ENV{DB2INSTANCE}; PROTOCOL=TCPIP",$ENV{USER},'adm4archive',{PrintError => 0, RaiseError => 1, ShowErrorStatement => 1, AutoCommit => 1, FetchHashKeyName => 'NAME_lc'});
	}
	$|=1;
	while (defined(my $sql = $q->dequeue())) {
		
		my $sel1 = $dh->prepare($sql);
		$sel1->execute;
		my $r = $sel1->fetchall_arrayref;
		$sel1->finish;
		my $fh;
		if ($outFile eq '-') {
			$fh = \*STDOUT;
		} else {
			open($fh,'>>',$outFile) || die "Unable to open outFile: $!\n";
		}
		flock($fh,2) || die "Unable to lock outFile: $!\n";
		$fh->autoflush;
		csv(in=>$r,out=>$fh,eol => "\n", binary => 1);
		if ($outFile eq '-') {
			flock($fh,LOCK_UN);
		} else {
			close($fh);
		}
	}
	$dh->disconnect;
}
