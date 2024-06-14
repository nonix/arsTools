#!/ars/odadm/bin/perl -w
use threads qw(yield);
use File::Path qw(make_path);
use Thread::Queue;
use strict;
# Expects:
# Param1 AGN
# STDIN sorted list "find DATA/DOC/TWA -type f |sort -t'/' -k4,4n"
# DATA/TWA/1FAA1
# DATA/TWA/1FAAA
# DATA/TWA/1GAA1
# DATA/TWA/1GAAA
# DATA/TWA/2FAA1
# DATA/TWA/2FAAA
# DATA/TWA/2GAA1

die "Usage: find DATA/DOC/AGN -type f |sort -t'/' -k4,4n|$0 AGN\n" unless (scalar(@ARGV));
my $AGN=shift;
my $nc=32000;	# dir counter
my $n=1;		# nth SUB
my $pd='';		# previous dir
my $ROOT="DATA/S3";
my $ql = Thread::Queue->new();
threads->create(\&doLink) for (1..18);

$|=1;
print "INFO: Process id $$\n";

print 'INFO: ',scalar(localtime())," Creating directory structure $ROOT/$AGN ...\n";
while (my $l=<>) {
	chomp $l;
	warn "WARNING: An empty file found: $l\n" unless (-s $l);
	chmod 0600,$l;
	my $fn=(split /\//,$l)[-1];
	if ($fn =~ /^\d+$/) {
		# It is a resource
    make_path("$ROOT/$AGN/SUB1/RES");
		$ql->enqueue("$l,$ROOT/$AGN/SUB1/RES/$fn");
	} elsif ($fn =~ /^(\d+\D{3}).*$/) {
		# It is a doc_name
		my $d = "$ROOT/$AGN/SUB$n/$1";
		if ($pd ne $d) {
      make_path($d);
			$pd=$d;
			$nc--;
		}
		$ql->enqueue("$l,$d/$fn");
		unless ($nc) {
			$nc=32000;
			$n++;
		}
	} else {
		warn "WARNING: An unknown file: $l\n";
		next;
	}
	
}

$ql->end;
print "INFO: Linking ...\n";
$_->join() for threads->list();

#qx/sms2nn link of $AGN finished/;
print 'INFO: ',scalar(localtime())," Finished with $AGN\n";

sub doLink {
	while (defined(my $e = $ql->dequeue())) {
		my ($src,$dst) = split(/,/,$e);
    next if (-f $dst);
		link $src,$dst || die "ERROR: Unable to link $src -> $dst\n";
	}
}
