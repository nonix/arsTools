#!/usr/bin/env perl

use warnings;
use strict;

use Config::IniFiles;

use File::Find qw(find);
use File::Basename qw(basename dirname);

my $config=Config::IniFiles->new( -file => dirname($0).'/config.ini', -fallback => 'all');
if (@Config::IniFiles::errors) {
  print "ERROR: ",@Config::IniFiles::errors,"\n";
  die "Problem with config.ini, please check\n";
}

die "Usage: $0 [-d|-l|-a]] AGID_NAME\n-a\tALL (default)\n-d\tData only\n-l\tLinks only\n" if (scalar(@ARGV)<1);
my $switch = '-a';
my $dir;
my $root = $config->val('all', 'CMOD_CACHE');

$switch = shift if (scalar(@ARGV) > 1);

unless (-f $config->val('all', 'CMOD_CFG')) {
  $root =  $config->val('all', 'CMOD_CACHE_DIR_SOURCE');
}

my $AGID_NAME=$ARGV[0];

if ($switch eq '-l') {
  $dir='retr';
} elsif ($switch eq '-d') {
  $dir='0';
} elsif ($switch eq '-a') {
  warn "ERROR: Cleanup of links failed\n" if (system("$0", '-l', $AGID_NAME));
  warn "ERROR: Cleanup of data failed\n"  if (system("$0", '-d', $AGID_NAME));
  exit;
} else {
  die "ERROR: Unknown switch $switch\n";
}

sub wanted1 {
    /^1.*\z/s
    && unlink($_);
}

sub wanted2 {
    /^2.*\z/s
    && unlink($_);
}

sub wanted3 {
    /^3.*\z/s
    && unlink($_);
}

sub wanted4 {
    /^4.*\z/s
    && unlink($_);
}

sub wanted5 {
    /^5.*\z/s
    && unlink($_);
}

sub wanted6 {
    /^6.*\z/s
    && unlink($_);
}

sub wanted7 {
    /^7.*\z/s
    && unlink($_);
}

sub wanted8 {
    /^8.*\z/s
    && unlink($_);
}

sub wanted9 {
    /^9.*\z/s
    && unlink($_);
}

my @wanted = (\&wanted1,\&wanted2,\&wanted3,\&wanted4,\&wanted5,\&wanted6,\&wanted7,\&wanted8,\&wanted9);

die "ERROR: Nothing to do; dir does not exists: $root/$dir/$AGID_NAME\n" unless (-d "$root/$dir/$AGID_NAME");

print "INFO: $0 $switch $AGID_NAME -- started at ",scalar(localtime(time)),"\n";

for my $f (@wanted) {
  my $pid = fork;
  die "ERROR: Unable to fork\n" unless (defined($pid));
  unless ($pid) {
    # I am a worker
    find({wanted=>$f},"$root/$dir/$AGID_NAME");
    exit;
  }
}

while (my $p=wait > -1) {
    print "INFO: $p finished\n";
}

rmdir "$root/$dir/$AGID_NAME/RES" if (-d "$root/$dir/$AGID_NAME/RES");
rmdir "$root/$dir/$AGID_NAME/DOC";
rmdir "$root/$dir/$AGID_NAME";
print "INFO: $0 $switch $AGID_NAME -- finished at ",scalar(localtime(time)),"\n";
