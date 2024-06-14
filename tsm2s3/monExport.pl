#!/ars/odadm/bin/perl -w
use strict;
die "Usage: $0 AGN [-s [secs]]\n" unless (scalar(@ARGV));
my $AGID_NAME=shift;
my $sample = 0;
if (defined($ARGV[0]) && ($ARGV[0] eq '-s')) {
  shift;
  $sample = 60;
  if (defined($ARGV[0])) {
    $sample = shift;
  }
}

if ($sample) {
  $|=1;
  print "INFO: Sampling for $sample seconds ...";
  my $start = qx/cat ${AGID_NAME}*.log|grep -cw Done/;
  sleep($sample);
  my $stop = qx/cat ${AGID_NAME}*.log|grep -cw Done/;
  my $count = qx/cat ${AGID_NAME}*.lst|wc -l/;
  my $fps = ($stop-$start)/$sample;
  printf("\nSpeed: %0.3lf doc(s)/minute\n",$fps*60);
  my $ttg = time()+(($count-$stop)/$fps);
  print 'ETA: ',scalar(localtime($ttg)),"\n";
} else {
  my $total = 0;
  my $done = 0;
  for my $f (glob("${AGID_NAME}*.{lst,log}")) {
    if ($f =~ /lst$/) {
      $total += qx/cat $f|wc -l/;
    } elsif ($f =~ /log$/) {
      $done += qx/cat $f|grep -cw Done/;
    }
  }
  if ($done && $total) {
    printf("Done: %0.2lf%%\n",$done/$total*100);
  } else {
    die "ERROR: Nothing found\n";
  }
}