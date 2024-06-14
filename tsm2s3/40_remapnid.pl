#!/ars/odadm/bin/perl -w
use DBI;
use strict;

die "Usage: $0 agid_name\n" unless (scalar(@ARGV));

my $AGID_NAME = shift;

$|=1;   # flush STDOUT often
print 'INFO: Started processing at ',scalar(localtime()),"\n";

my $DBUSER='odadm';
my $DBPASSWD='adm4archive';
my $TCPPORT='db2c_agarch';
my $DBCONNECT='DATABASE='.$ENV{DB2INSTANCE}.'; HOSTNAME=localhost; PORT='.$TCPPORT.'; PROTOCOL=TCPIP';
print "INFO: Update stats for SC_$AGID_NAME\n";
system("/ars/odadm/bin/update_stats.sh SC_$AGID_NAME");

my $dh = DBI->connect('dbi:DB2:'.$DBCONNECT,$DBUSER,$DBPASSWD,{PrintError => 0, RaiseError => 1, ShowErrorStatement => 1, AutoCommit => 0, FetchHashKeyName => 'NAME_lc'});

my $rows=0;

my $seg_ref = $dh->selectcol_arrayref(qq/
select seg.table_name from arsag ag
inner join arsseg seg
  on seg.agid=ag.agid
where ag.agid_name=? order by 1
/,undef,$AGID_NAME);

my ($agid, $nid) = $dh->selectrow_array(qq/
select ag.agid, n.nid from arsag ag 
  inner join arsnode n 
  on ag.sid = n.sid
  and bitand(n.status,2621442)=2621442
where ag.agid_name=?/,undef,$AGID_NAME);

die "ERROR: Unable to get the S3 nid for $AGID_NAME\n" unless ($nid);

# update arsres
$rows = $dh->do(qq/update arsres res set pri_nid=$nid where pri_nid between 2 and 10 and agid=$agid
                    and varchar(rid) in (select name from SC_$AGID_NAME where type='R' and status=2)
/);
$rows=($rows == '0E0')?0:$rows;
print "INFO: $rows row(s) affected in arsres\n";
$dh->commit;

# Update SC_AGN where type='R'
$rows = $dh->do(qq/update SC_$AGID_NAME set status=3 where status=2 and type='R' and name in (select varchar(rid) from arsres where pri_nid=$nid and agid=$agid)
/);
$dh->commit;


# update arsload
$rows = $dh->do(qq/
update arsload t set pri_nid=$nid 
where agid=$agid and pri_nid between 2 and 10 and exists 
(select 1 from SC_$AGID_NAME where left(name,locate(trim(translate(name,'','0123456789')),name)-1)||
    substr(name,length(left(name,locate(trim(translate(name,'','0123456789')),name)-1))+1,3)=t.name 
    and type='D' and status=2)
/);

$rows=($rows == '0E0')?0:$rows;
print "INFO: $rows row(s) affected in arsload\n";
$dh->commit;

for my $seg (@$seg_ref) {
	$dh->do(qq/alter table $seg ACTIVATE NOT LOGGED INITIALLY/);
  $rows = $dh->do(qq/
    update $seg t set pri_nid=$nid where pri_nid between 2 and 10 and translate(doc_name,'','\$') in 
    (select name from SC_$AGID_NAME where type='D' and status=2)
/);
  $rows=($rows == '0E0')?0:$rows;
  print "INFO: $rows row(s) affected in $seg\n";
  $dh->commit;
  
	$dh->do(qq/alter table SC_$AGID_NAME ACTIVATE NOT LOGGED INITIALLY/);
  $rows = $dh->do(qq/
  update SC_$AGID_NAME set status=3 where type='D' and status=2 and name in (select translate(doc_name,'','\$') from $seg where pri_nid=$nid)
/);
  $dh->commit;
}

END {
	if (defined($dh)) {
		$dh->commit;
		$dh->disconnect;
	}
  print 'INFO: Finished processing at ',scalar(localtime()),"\n";
  qx/sms2nn "Finished remaping $AGID_NAME"/;
}
