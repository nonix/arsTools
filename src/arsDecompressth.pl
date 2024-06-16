#!/ars/odadm/bin/perl -w
use threads;
use threads::shared;
use Thread::Queue;
use Fcntl qw(:flock :DEFAULT SEEK_SET);
use Compress::Raw::Zlib;
use strict;


my $q = Thread::Queue->new();
my $NTHREADS = 24;
$q->limit = $NTHREADS*8;

sub worker {
  my $infile = '';
  my $infh;
  while (my $task = $q->dequeue()) {
    warn 'DEBUG: TID: ',threads->tid()," got task:$task\n" if ($ENV{DEBUG});
    my @p = split(/:/,$task);
    if ($p[0] ne $infile) {
      $infile = $p[0];
      close($infh) if (defined($infh));
      open($infh,'<:raw',$infile)|| die "ERROR: sysopen: $!";
    }

    my ($input, $output) = ('','');
    seek($infh,$p[1],SEEK_SET) || die "ERROR: Seek: $!";
    read($infh, $input, $p[2]) || die "ERROR: read: $!";
    
    my $zlib = new Compress::Raw::Zlib::Inflate() || die "ERROR: Can't create decompressor";
    my $status = $zlib->inflate($input, $output);
    if ((($status == Z_OK) || ($status == Z_STREAM_END)) && $output) {
      my $outfile = join('.',$infile,$p[1]);
      open(my $outfh,'>:raw',$outfile)|| return warn "ERROR: open $outfile TID:",threads->tid()," $!";
      binmode $outfh ||return warn 'ERROR: binmode TID:',threads->tid()," $!";
      print ($outfh $output)|| return warn 'ERROR: print TID:',threads->tid()," $!";
      close($outfh);
    } else {
      warn "WARNING: Decompress failed for $infile at offset1: $p[1].$p[2]\n";
    }

  }
  close($infh) if (defined($infh));
}

my $feed;
my ($doc_name,$comp_off,$comp_len);

sub usage {
  die "Usage: $0 -|feedFile|(doc_name comp_off comp_len)\n";
}

if (scalar(@ARGV) == 0) {
  usage;
} elsif ($ARGV[0] eq '-') {
  $feed = \*STDIN;
  warn "DEBUG: Reading feed from STDIN\n"  if ($ENV{DEBUG});
} elsif (scalar(@ARGV) > 1) {
  ($doc_name,$comp_off,$comp_len) = @ARGV;
  $NTHREADS = 1; # no need to start more than 1
} elsif (-f $ARGV[0]) {
  open($feed,'<',$ARGV[0]) || die "ERROR: Open input: $!";
} else {
  usage;
}

# Start the threds
threads->create(\&worker) for (1..$NTHREADS);

if (defined($doc_name)) {
  $q->enqueue(join(':',$doc_name,$comp_off,$comp_len));
} else {
  while (<$feed>) {
    chomp;
    next if (/^\#/); # skip comment
    $q->enqueue(join(':',split(/[\s,:;]+/)));
  }
}

# closing
$q->end();
$_->join() for (threads->list());
