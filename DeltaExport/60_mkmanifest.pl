#!/usr/bin/env perl

use warnings;
use strict;

use DBI;
use Number::Format 'format_number';
use Config::IniFiles;

use threads qw(yield);
use threads::shared;
use Thread::Queue;
use Data::Dumper;
use File::Basename qw(basename dirname);

# Get number of CPUs
# /usr/sbin/lsdev -C -c processor

my $config=Config::IniFiles->new( -file => dirname($0).'/config.ini', -fallback => 'all');
if (@Config::IniFiles::errors) {
  print "ERROR: ",@Config::IniFiles::errors,"\n";
  die "Problem with config.ini, please check\n";
}

my %stat :shared;
my $todo :shared=0;
my $q;
my $nthreads = 8;
my $basedir=$config->val('all', 'CMOD_REMOTE').'/EXPORT';
$basedir=$ENV{BASEDIR} if ($ENV{BASEDIR});

sub usage{
  die "Usage: $0 AGID_NAME |-r agmap\nUsing BASEDIR: $basedir\n";
}

sub worker {
  while (my $x = $q->dequeue) {
    my @t = split(/\./,$x);
    my $xap = $t[$#t-1];
    my %r1;
    open(my $fh,'<',$x)||die;
    while (my $l=<$fh>) {
      if ($l =~ /^(GROUP_FILENAME|GROUP_ANNOTATION_FILE):/) {
        $r1{$1}++;
      } elsif ($l =~ /^(GROUP_LENGTH):(\d+)/) {
        $r1{$1} = 0 unless (defined($r1{$1}));
        $r1{$1} += $2;
      }
    }
    close($fh);
    # Update results
    { lock(%stat);
      if (ref($stat{cnt}->{$xap})) {
        for (keys(%r1)) {
          $stat{cnt}->{$xap}->{$_} = 0 unless (defined($stat{cnt}->{$xap}->{$_}));
          $stat{cnt}->{$xap}->{$_} += $r1{$_};
        }
      } else {
        $stat{cnt}->{$xap} = shared_clone(\%r1);
      }
    }
    {
      lock($todo);
      $todo--;
    }
  }
}

usage() unless (scalar(@ARGV));
$|=1; #Flush stdout

# Process switches (simple)
my %opt;
if ($ARGV[0] eq '-r') {
  $opt{mode}='r';
  print "Remove all manifests\n";
} elsif ($ARGV[0] =~ /^(\D{3})$/) {
  $opt{AGID_NAME}=uc($1);
  $opt{mode}='s';
  print "Compute statistics\n";
} else {
    usage();
}
shift;

# Load mapping
my $where;
my $dh = DBI->connect('dbi:DB2:DATABASE=ENTARCHC; HOSTNAME=sb000299.rba-fb.ch; PORT=50000; PROTOCOL=TCPIP','odadm','2wsx.3edc',
  {PrintError => 0, RaiseError => 1, ShowErrorStatement => 1, AutoCommit => 1, FetchHashKeyName => 'NAME_lc'});

if ($opt{AGID_NAME}) {
  $where = qq/agid_name = \'$opt{AGID_NAME}\'/;
} else {
  $where = q/1=1/;
}

# agid_name as key, agname as value
my %map = @{$dh->selectcol_arrayref(qq/select agid_name,name from arsag where name not like 'System%' and $where/, { Columns=>[1,2] })};
$dh->disconnect;

my $DEBUG;
if ($DEBUG) {
  print 'map{',$_,'}=',$map{$_},"\n" for (keys(%map));
}

if ($opt{mode} eq 'r') {
  # Removal mode
  for my $ag (keys(%map)) {
    my $fn = $basedir.'/'.$map{$ag}.'.manifest';
    if (-f $fn) {
      unlink $fn;
      print "$fn\tRemoved!\n";
    }
  }
} elsif ($opt{mode} eq 's') {
  # Statistics mode
  $q = Thread::Queue->new();
  $q->limit = 1000;
  threads->create(\&worker) for (1..$nthreads);
  for my $ag (keys(%map)) {
    my $dir = $basedir.'/'.$ag;
    my $fn = $basedir.'/'.$ag.'.manifest';
    unless (-f $fn) {
      print "Writing statistics: $fn";
      for my $d (glob($dir.'/'.$ag.'?*')) {
        next unless ( -d $d);
#        print "\nDEBUG: Dir => $d\n";
        for my $x (glob($d.'/*/*')) {
          if ($x =~ /\.(out|res)$/) {
            my $k = $1;
            lock(%stat);
            $stat{$k} = 0 unless (defined($stat{$k}));
            $stat{$k} += (-s $x);
          } elsif ($x =~ /\.ind$/) {
            my @t = split(/\./,$x);
            { lock(%stat);
              my $k = $t[$#t-1];
              $stat{cnt} = shared_clone({$k=>{}}) unless (ref($stat{cnt}));
            }
            {
            lock($todo);
            $todo++;
            }
            $q->enqueue($x);
          }
        }
      }
      open(my $f,'>>',$fn)||die "$!";
      print $f "Statistics\n==========\n";
      print $f 'Application group: ',$map{$ag},"\n";
      while ($todo) { sleep(1); }
        warn "Debug:\n",Dumper(\%stat),"\n" if ($DEBUG);
      if (defined($stat{out})) {
        print $f 'Total payload size on disk in bytes: ',format_number($stat{out}),"\n";
        print $f 'Total resource size on disk in bytes: ',format_number(defined($stat{res})?$stat{res}:0),"\n";
        for my $app (keys(%{$stat{cnt}})) {
          print $f 'Application: ',$app,"\n";
          print $f "\t",'Document count: ',format_number($stat{cnt}->{$app}->{GROUP_FILENAME}),"\n";
          print $f "\t",'Document size (computed from .ind): ',format_number($stat{cnt}->{$app}->{GROUP_LENGTH}),"\n";
          print $f "\t",'Annotation count: ',format_number(defined($stat{cnt}->{$app}->{GROUP_ANNOTATION_FILE})?$stat{cnt}->{$app}->{GROUP_ANNOTATION_FILE}:0),"\n";
        }
        print $f "\n";
        close($f);
      } else {
        print $f "Seems not exported, yet\n";
      }
      undef %stat;
      print "\tdone\n";
    }
  }
  # Close the queue and finish threads
  $q->end();
  $_->join() for threads->list();
}
print "Done\n";
