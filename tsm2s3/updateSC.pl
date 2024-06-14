#!/ars/odadm/bin/perl -w
use DBI;
use strict;

my $DBUSER='odadm';
my $DBPASSWD='adm4archive';
my $TCPPORT='db2c_agarch';
my $DBCONNECT='DATABASE='.$ENV{DB2INSTANCE}.'; HOSTNAME=localhost; PORT='.$TCPPORT.'; PROTOCOL=TCPIP';

die join("\n","Usage: doc_name(s)|$0 AGID_NAME status [doc_name.lst]",'1 = exported','2 = uploaded','3 = pri_nid switched','') unless (scalar(@ARGV));
my $AGID_NAME = shift;
my $STATUS = shift;

my $dh = DBI->connect('dbi:DB2:'.$DBCONNECT,$DBUSER,$DBPASSWD,{PrintError => 0, RaiseError => 1, ShowErrorStatement => 1, AutoCommit => 0, FetchHashKeyName => 'NAME_lc'});
if ($STATUS eq '-l') {
  # List current, don't update
  
  print "ALL data for $AGID_NAME\n";
  my $sel = $dh->prepare(qq/
    select status,type,count(*) as count from SC_$AGID_NAME group by status,type order by 1,2
    /);
  $sel->execute();
  print "status, type, count\n";
  while (my $l = $sel->fetch) {
    print join(', ',@$l),"\n";
  }
  $dh->commit;
  $sel->finish;
  print "\nIDX excluded\n";
  $sel = $dh->prepare(qq/
    select status,type,count(*) as count from (select * from SC_$AGID_NAME where type='R' union  select * from SC_$AGID_NAME where type!='R' and name not like '%1') group by status,type order by 1,2
    /);
  $sel->execute();
  print "status, type, count\n";
  while (my $l = $sel->fetch) {
    print join(', ',@$l),"\n";
  }
  $dh->commit;
  $sel->finish;
} else {
  my $upd = $dh->prepare(qq/
    update SC_$AGID_NAME set status=$STATUS where name=? and status = ${STATUS}-1
  /);
  my $rc = 0;
  while (<>) {
    chomp;
    next unless (/^\d/);
    $upd->execute($_);
    unless ($upd->rows) {
      warn "WARN: $AGID_NAME/$_ not matched where status=",($STATUS-1),"\n";
    } else {
      $rc += $upd->rows;
    }
    unless ($. % 1000) {
      warn "INFO: $rc row(s) updated\n";
      $dh->commit ;
    }
  }
  $dh->commit;
  $upd->finish;
  warn "INFO: Total of $rc row(s) updated\n";
}
$dh->disconnect;

