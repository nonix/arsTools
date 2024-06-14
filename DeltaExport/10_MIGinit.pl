#!/usr/bin/env perl

use strict;
use warnings;

use DBI;
use Config::IniFiles;
use Try::Tiny;

use threads qw(yield);
use threads::shared;
use Thread::Queue;
use Data::Dumper;
use File::Find qw(find);
use File::Basename qw(basename dirname);

die "Usage: $0 agid_name [mkpar]\n" unless (scalar(@ARGV));

my $PRG_DIRNAME=dirname($0);
my $config=Config::IniFiles->new( -file => ${PRG_DIRNAME}.'/config.ini', -fallback => 'all');
if (@Config::IniFiles::errors) {
  print "ERROR: ",@Config::IniFiles::errors,"\n";
  die "Problem with config.ini, please check\n";
}

my $AGID_NAME=$ARGV[0];
my $NTH = 12;
my $MKPAR=defined($ARGV[1]);
my $PARDIR = $config->val('all', 'CMOD_PARS');
my $BATCHSIZE = 20000;
print "INFO: $0 $ARGV[0] -- Started at ",scalar(localtime(time)),"\n";
my $dh;
my @segs;

$dh = DBI->connect('dbi:DB2:DATABASE='.$config->val('all', 'DB2_INSTANCE').'; HOSTNAME='.$config->val('all', 'DB2_HOSTNAME').'; PORT='.$config->val('all', 'DB2_PORT').'; PROTOCOL=TCPIP',$config->val('all', 'DB2_USER'),$config->val('all', 'DB2_PWD'),
  {PrintError => 0, RaiseError => 1, ShowErrorStatement => 1, AutoCommit => 1, FetchHashKeyName => 'NAME_lc'});

# Get AGID and AGNAME
my ($AGID,$AGNAME) = $dh->selectrow_array(qq/select agid,name from arsag where agid_name=upper(?)/,undef,$AGID_NAME);
die "ERROR: $AGID_NAME not found" unless ($AGID);

try {
  $dh->do(qq/CREATE TABLE MIG_$AGID_NAME (SEGMENT VARCHAR(18) NOT NULL, DOC_NAME VARCHAR(11) NOT NULL, TID BIGINT NOT NULL, status smallint not null default 0)/);
  $dh->do(qq/create unique index MIG_$AGID_NAME\_1 on MIG_$AGID_NAME(doc_name)/);
  $dh->do(qq/create index MIG_$AGID_NAME\_2 on MIG_$AGID_NAME(tid)/);
  $dh->do(qq/create index MIG_$AGID_NAME\_3 on MIG_$AGID_NAME(status)/);
  @segs = @{$dh->selectall_arrayref(qq/select table_name,to_char(start_dt,'YYYY-MM-DD') as start_dt,to_char(stop_dt,'YYYY-MM-DD') as stop_dt from arsseg where agid=? order by int(substr(table_name,4))/,{ Slice => {} },$AGID)};
} catch {
  warn "INFO: MIG_$AGID_NAME already exists. Drop it if you would like to re-run, otherwise will just backfill i.e. delta\n";
  my ($lastseg) = $dh->selectrow_array(qq/select  max(int(right(segment,length(segment)-length(trim(translate(segment,'','0123456789')))))) as lastseg from MIG_${AGID_NAME}/);

  if ($MKPAR) {
      @segs = @{$dh->selectall_arrayref(qq/select table_name,to_char(start_dt,'YYYY-MM-DD') as start_dt,to_char(stop_dt,'YYYY-MM-DD') as stop_dt from arsseg where agid=? order by int(substr(table_name,4))/,{ Slice => {} },$AGID)};
  } else {
    @segs = @{$dh->selectall_arrayref(qq/select table_name,to_char(start_dt,'YYYY-MM-DD') as start_dt,to_char(stop_dt,'YYYY-MM-DD') as stop_dt from arsseg where agid=? and int(right(table_name,length(table_name)-length(trim(translate(table_name,'','0123456789'))))) >= ? order by int(substr(table_name,4))/,{ Slice => {} },($AGID,$lastseg))};
  }
};

unless ($MKPAR) { # Skip if MKPAR only

my $q;  # Queue of refs
$q = Thread::Queue->new();
$q->limit = 1000;
my $lck :shared =0;
$|=1;

sub slicer {
  $dh = DBI->connect('dbi:DB2:DATABASE='.$config->val('all', 'DB2_INSTANCE').'; HOSTNAME='.$config->val('all', 'DB2_HOSTNAME').'; PORT='.$config->val('all', 'DB2_PORT').'; PROTOCOL=TCPIP',$config->val('all', 'DB2_USER'),$config->val('all', 'DB2_PWD'),
    {PrintError => 0, RaiseError => 1, ShowErrorStatement => 1, AutoCommit => 1, FetchHashKeyName => 'NAME_lc'});
  my $ih = $dh->prepare(qq/insert into MIG_$AGID_NAME (segment,doc_name,tid) values (?,?,?)/);
  while(my $seg = $q->dequeue) {
    # Loading MIG_ table, get rec count by doc_name for doc_name not yet known in MIG table
    my $sh = $dh->prepare(qq/select count(*) as count,doc_name from $seg->{table_name} where doc_name not in (select doc_name from MIG_$AGID_NAME) group by doc_name/);
    $sh->execute;
    my $tid = 0;
    my $sum = 0;
    while(my $r = $sh->fetchrow_hashref) {
      try {
      $ih->execute($seg->{table_name},$r->{doc_name},$tid);
      } catch {
        lock($lck);
    
        if ($ih->err == -803) {
          print join(' ',$seg->{table_name},$r->{doc_name},'seen'),"\n";
        } else {
          die $ih->errstr;
        }
      };
      $dh->{RaiseError}=1;
      $sum += $r->{count};
      if ($sum >= $BATCHSIZE) {
        $sum = 0;
        ++$tid;
      }
    }
    {
      lock($lck);
#      print $seg->{table_name},' ',$tid,"\n";
    }
    $sh->finish;
    yield;
  }
  $ih->finish;
  $dh->disconnect;  
} # slicer

# Start the workers
threads->create(\&slicer) for (1..$NTH);

# Fill the MIG_ table
warn "INFO: Filling MIG_$AGID_NAME\n";
for my $r (@segs) {
  # print 'Segment: ',$r->{table_name},', Start_dt: ',$r->{start_dt},"\n";
  $q->enqueue($r);
}

# Wait for threads to finish
$q->end();
$_->join() for threads->list();
}
$dh->disconnect;

my $DB2_INSTANCE=$config->val('all', 'DB2_INSTANCE');
qx/export DB2DATABASE=${DB2_INSTANCE};${PRG_DIRNAME}\/__update_stats.sh MIG_$AGID_NAME/;


$dh = DBI->connect('dbi:DB2:DATABASE='.$config->val('all', 'DB2_INSTANCE').'; HOSTNAME='.$config->val('all', 'DB2_HOSTNAME').'; PORT='.$config->val('all', 'DB2_PORT').'; PROTOCOL=TCPIP',$config->val('all', 'DB2_USER'),$config->val('all', 'DB2_PWD'),
  {PrintError => 0, RaiseError => 1, ShowErrorStatement => 1, AutoCommit => 1, FetchHashKeyName => 'NAME_lc'});

warn "INFO: Write PARS\n";

# Delete all existing PARs first
system('rm','-f',glob(qq(${PARDIR}/${AGID_NAME}*))) && warn "WARN: Unable to delete PARS\n";

my $sh=$dh->prepare(qq/select distinct tid from MIG_${AGID_NAME} where segment=? and status!=2/);
#DEBUG print Dumper(\@segs),"\n";
for my $seg (@segs) {
  $sh->execute($seg->{table_name});
  while(my $r = $sh->fetch) {
      my ($tid) = @$r;
      my $p = '[-d '.$config->val('all', 'CMOD_EXPORT').'/'.$AGID_NAME.'/%S/%T][-u admin][-a][-c][-g][-N][-A3][-G "'.$AGNAME.
        '"][-i "where doc_name in (select doc_name from MIG_'.$AGID_NAME.' where segment='."\'".'%S'."\'".' and tid=%T and status=1)"][-o ED22][-S %D]';
      $p =~ s/%S/$seg->{table_name}/g;  # Subst. all Segment
      $p =~ s/%T/$tid/g;  # Subst. all TID
      $p =~ s/%D/$seg->{start_dt},$seg->{stop_dt}/; # Subst. date
#DEBUG      print 'INFO: ',$PARDIR.'/'.$seg->{table_name}.'.'.$tid.'.par',"\n";
      open(my $fh,'>',$PARDIR.'/'.$seg->{table_name}.'.'.$tid.'.par')||die $!;
      print $fh $p,"\n";
      close($fh);
  }
}
$sh->finish;

END {
  $dh->disconnect if (defined($dh));
  print "INFO: $0 -- Finished at ",scalar(localtime(time)),"\n";
}
