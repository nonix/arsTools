#!/usr/bin/env perl

use warnings;
use strict;

use Config::IniFiles;

use threads qw(yield);
use Thread::Queue;
use File::Basename qw(basename dirname);
use File::Find qw(find);

die "Usage: $0 AGID_NAME\n\treq.: CACHEDIR env\n" unless (scalar(@ARGV));
print "INFO: $0 $ARGV[0] -- Started at ",scalar(localtime(time)),"\n";
my $AGID_NAME = $ARGV[0];

my $config=Config::IniFiles->new( -file => dirname($0).'/config.ini', -fallback => 'all');
if (@Config::IniFiles::errors) {
  print "ERROR: ",@Config::IniFiles::errors,"\n";
  die "Problem with config.ini, please check\n";
}

#die "ERROR: env. CACHEDIR is not set (incl. the srv. name)\n" unless (${CACHEDIR});
my $CACHEDIRTARGET=$config->val('all', 'CMOD_CACHE_DIR_TARGET');
my $CACHEDIRSOURCE=$CACHEDIRTARGET;
if (! -d $CACHEDIRSOURCE) {
  $CACHEDIRSOURCE=$config->val('all', 'CMOD_CACHE_DIR_SOURCE');;
}

my $q = Thread::Queue->new();
   $q->limit = 10000;
my $NTH = 6;
$|=1;

sub queuesrc {
  if (-f $_) {
      $q->enqueue($_);
  }
}


sub doclinker {
  while (my $s = $q->dequeue) {
    my $d = "$CACHEDIRSOURCE/retr/$AGID_NAME/DOC/$s";
    my $sSource = "${CACHEDIRSOURCE}/0/$AGID_NAME/DOC/$s";
    my $sTarget = "${CACHEDIRTARGET}/0/$AGID_NAME/DOC/$s";
    chmod(0400,$sSource);
    symlink($sTarget,$d);
    yield;
  }
}

sub reslinker {
  while (my $s = $q->dequeue) {
    my $d = "${CACHEDIRSOURCE}/retr/$AGID_NAME/RES/$s";
    my $sSource = "${CACHEDIRSOURCE}/0/$AGID_NAME/RES/$s";
    my $sTarget = "${CACHEDIRTARGET}/0/$AGID_NAME/RES/$s";
    chmod(0400,$sSource);
    symlink($sTarget,$d);
    yield;
  }
}

# DOC linker
chmod(0700,"${CACHEDIRSOURCE}/0/$AGID_NAME");
chmod(0700,"${CACHEDIRSOURCE}/0/$AGID_NAME/DOC");
mkdir "${CACHEDIRSOURCE}/retr/$AGID_NAME",0700 unless (-d "${CACHEDIRSOURCE}/retr/$AGID_NAME");
mkdir "${CACHEDIRSOURCE}/retr/$AGID_NAME/DOC",0700 unless (-d "${CACHEDIRSOURCE}/retr/$AGID_NAME/DOC");
threads->create(\&doclinker) for (1..$NTH);
print "INFO: Linking DOC ...\n";
find({wanted => \&queuesrc},"${CACHEDIRSOURCE}/0/$AGID_NAME/DOC");
$q->end();
$_->join() for threads->list();


# RES linker
if (-d "${CACHEDIRSOURCE}/0/$AGID_NAME/RES") {
  chmod(0700,"${CACHEDIRSOURCE}/0/$AGID_NAME/RES");
  mkdir "${CACHEDIRSOURCE}/retr/$AGID_NAME/RES",0700 unless (-d "${CACHEDIRSOURCE}/retr/$AGID_NAME/RES");
  $q = Thread::Queue->new();
  $q->limit = 10000;
  threads->create(\&reslinker) for (1..$NTH);
  print "INFO: Linking RES ...\n";
  find({wanted => \&queuesrc},"${CACHEDIRSOURCE}/0/$AGID_NAME/RES");
  $q->end();
  $_->join() for threads->list();
}
print "INFO: $0 -- Finished at ",scalar(localtime(time)),"\n";
