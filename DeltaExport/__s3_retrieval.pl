#!/usr/bin/env perl

use warnings;
use strict;

use DBI;
use Config::IniFiles;

use File::Basename qw(basename dirname);
use File::Find qq(find);

die "Usage: $0 AGID_NAME\n" unless (scalar(@ARGV) == 1);
my $AGIDNAME=shift;

my $config=Config::IniFiles->new( -file => dirname($0).'/config.ini', -fallback => 'all');
if (@Config::IniFiles::errors) {
  print "ERROR: ",@Config::IniFiles::errors,"\n";
  die "Problem with config.ini, please check\n";
}

my $mig="MIG_${AGIDNAME}";
# /ars/ent/data/arscache/ENTARCHC
my $BASEDIR=$ENV{CACHEDIR};
die "ERROR: env. CACHEDIR not set." unless ($BASEDIR);
my $DATADIR=$BASEDIR.'/0';
my $RETR=$BASEDIR.'/retr';
my $S3BUCKET=$config->val('all', 'CMOD_S3_BUCKET');
my $S3PROFILE=$config->val('all', 'CMOD_S3_PROFILE');

# Get files in cache
my %cache;

sub wanted {
    my ($dev,$ino,$mode,$nlink,$uid,$gid);

#    (($dev,$ino,$mode,$nlink,$uid,$gid) = lstat($_)) &&
    if (-f $_) {
      s/^(\d+\D{3}).+$/$1/;
      $cache{$_}=1;
    }
}

if (-d "$DATADIR/$AGIDNAME/DOC" ) {
  warn "INFO: Cache backfill for DOC ...\n";
  find(\&wanted,"$DATADIR/$AGIDNAME/DOC");
  # open(my $p,"ls -1 $DATADIR/$AGIDNAME/DOC|")||die "ERROR: Unable to fork";
  # while (<$p>) {
      # chomp;
      # s/^(\d+\D{3}).+$/$1/;
      # $cache{$_} = 1;
  # }
  # close($p);
} # Otherwise don't bother ...
# Try RES
if (-d "$DATADIR/$AGIDNAME/RES" ) {
  warn "INFO: Cache backfill for RES ...\n";
  find(\&wanted,"$DATADIR/$AGIDNAME/RES");
  # open(my $p,"ls -1 $DATADIR/$AGIDNAME/RES|")||die "ERROR: Unable to fork";
  # while (<$p>) {
      # chomp;
      # $cache{$_} = 1;
  # }
  # close($p);
} # Otherwise don't bother ...


# Check the requested loadid if exists in the cache or not
# Create data dir if not present
my $RESDIR = "$DATADIR/$AGIDNAME/RES";
$DATADIR .= "/$AGIDNAME/DOC";
qx/mkdir -p $DATADIR/ unless (-d $DATADIR);

# Connect to DB2 and get list os resp segments
my $dh = DBI->connect('dbi:DB2:DATABASE='.$config->val('all', 'DB2_INSTANCE').'; HOSTNAME='.$config->val('all', 'DB2_HOSTNAME').'; PORT='.$config->val('all', 'DB2_PORT').'; PROTOCOL=TCPIP',$config->val('all', 'DB2_USER'),$config->val('all', 'DB2_PWD'),
  {PrintError => 0, RaiseError => 1, ShowErrorStatement => 1, AutoCommit => 1, FetchHashKeyName => 'NAME_lc'});
my @segs=@{$dh->selectcol_arrayref(qq/select distinct segment from MIG_$AGIDNAME where status=0/)};
for my $seg (@segs) {
    my $sel = $dh->prepare(qq/select distinct left(doc_name,locate(translate(doc_name,'','0123456789',''),doc_name)-1)||left(translate(doc_name,'','0123456789',''),3) 
                                from $seg where pri_nid>0 and doc_name in (select doc_name from $mig where status=0)
                              union
                              select distinct cast(resource as varchar(10))
                                from $seg where pri_nid>0 and resource>0 and doc_name in (select doc_name from $mig where status=0)
                              order by 1/);
    $sel->execute;
    while (my $r = $sel->fetch) {
      my $doc = $r->[0];
      unless (defined($cache{$doc})) {
          $cache{$doc}=1;
          if ($doc=~/^\d+$/) {
             # This RES
             mkdir $RESDIR unless (-d $RESDIR);
            print "aws s3 cp $S3BUCKET/$AGIDNAME/RES/$doc $RESDIR/ --no-progress --profile $S3PROFILE\n";
          } else {
            # This is DOC
            print "aws s3 cp $S3BUCKET/$AGIDNAME/$doc $DATADIR/ --recursive --no-progress --profile $S3PROFILE\n";
          }
      } else {
          warn "INFO: $doc Found in cache ...\n";
      }
  }
  $sel->finish;
}
$dh->disconnect;
