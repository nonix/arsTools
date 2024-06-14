#!/ars/odadm/bin/perl -w
use DBI;

my $OUTDIR='DATA/SQL/';
my $DBUSER='odadm';
my $DBPASSWD='adm4archive';
my $TCPPORT='db2c_agarch';
my $DBCONNECT='DATABASE='.$ENV{DB2INSTANCE}.'; HOSTNAME=localhost; PORT='.$TCPPORT.'; PROTOCOL=TCPIP';

die "Usage: $0 [-h][-r]\n-r\tReset\n" if (scalar(@ARGV) && ($ARGV[0] eq '-h'));

sub writeSQL {
  my ($prt_ref,$agid_name) = @_;
  print "INFO: Writing ... SC_$agid_name\n";
  
  # open sql
  open(my $sql,'>',qq/${OUTDIR}SC_${agid_name}.sql/) || die "$!";
  
  # Create unique index
  push @$prt_ref,qq/create unique index SC_${agid_name}_UX on SC_${agid_name} (name)/;

  # Update stats
  push @$prt_ref,qq/RUNSTATS ON TABLE SC_$agid_name/;

  push @$prt_ref,qq/RUNSTATS ON TABLE SC_$agid_name FOR INDEXES ALL/;

  # terminate (will be sliced to separate files).
  push @$prt_ref,'terminate';
  
  # print @$prt_ref
  print $sql join(";\n",@$prt_ref),";\n";
  
  # Close SQL
  close($sql);
  
  # Empty buffer
  @$prt_ref = ();  
}


my $RESET = q//;

my $dh = DBI->connect('dbi:DB2:'.$DBCONNECT,$DBUSER,$DBPASSWD,{PrintError => 0, RaiseError => 1, ShowErrorStatement => 1, AutoCommit => 1, FetchHashKeyName => 'NAME_lc'});

my $tbls = $dh->prepare(qq/select ag.agid,ag.agid_name,seg.table_name from arsag ag inner join arsseg seg on 
ag.agid = seg.agid where ag.name not like 'System%' or ag.name = 'System Log' order by 2/);

$tbls->execute;

my @prt;
my $prev_agid_name='';
while (my $tbl_r = $tbls->fetch) {
  my ($AGID,$AGID_NAME,$TABLE_NAME) = @$tbl_r;
# my $d = $dh->selectcol_arrayref(qq/select 'drop table '||name||';' from sysibm.systables where name = 'SC_$AGID_NAME'/);

  if ($prev_agid_name ne $AGID_NAME) {
    if ($prev_agid_name) {
        writeSQL(\@prt,$prev_agid_name);
    }
    $prev_agid_name = $AGID_NAME;
    if (scalar(@ARGV) && ($ARGV[0] eq '-r')) {
      $RESET = q/WITH EMPTY TABLE/;
    } else {
      $RESET = q//;
    }

  }
  # Connect to DB2
  push @prt,qq/connect to AGARCH/;
  
  # Create table
  push @prt,(qq/
create table if not exists SC_$AGID_NAME 
  (name varchar(11) not null,
   node varchar(128) not null,
   type char(1) not null default 'D',
   status integer not null default 0)
/,q/commit/);
  
  # Alter table
  push @prt,qq/
alter table SC_$AGID_NAME ACTIVATE NOT LOGGED INITIALLY $RESET
/;
  $RESET = q//;

  unless ($AGID_NAME eq 'SL') {
    # Merge docs
    push @prt, qq/
merge into SC_$AGID_NAME sc 
using (select distinct translate(trim(doc_name),'','\$','') as doc_name,lower(n.logon) as logon from $TABLE_NAME s
    inner join arsnode n
        on s.pri_nid = n.nid
    inner join arsag ag
        on n.sid = ag.sid
        and ag.agid_name='$AGID_NAME'
where s.pri_nid between 2 and 10
        union 
      select distinct left(doc_name,locate(trim(translate(doc_name,'','0123456789')),doc_name)-1)|| left(trim(translate(doc_name,'','0123456789')),3)||'1' as doc_name,lower(n.logon) as logon from $TABLE_NAME s
    inner join arsnode n
        on s.pri_nid = n.nid
    inner join arsag ag
        on n.sid = ag.sid
        and ag.agid_name='$AGID_NAME'
where s.pri_nid between 2 and 10) t 
on (sc.name = t.doc_name and sc.type = 'D') 
when not matched then 
  insert (name,node) values (t.doc_name,t.logon)
/;

    # Merge resources
    push @prt, qq/
merge into SC_$AGID_NAME sc using 
(select distinct trim(resource) as doc_name,lower(n.logon) as logon from $TABLE_NAME s
    inner join arsnode n
        on s.pri_nid = n.nid
    inner join arsag ag
        on n.sid = ag.sid
        and ag.agid_name='$AGID_NAME'
where s.pri_nid between 2 and 10 and int(resource)>0) t
on (sc.name = t.doc_name and sc.type = 'R')
when not matched then
  insert (type,name,node) values ('R',t.doc_name,t.logon)
/;
  } else {
    # Merge System Log
    push @prt,qq/
merge into SC_SL sc 
using (select distinct trim(doc_name) as doc_name,lower(n.logon) as logon from $TABLE_NAME s
    inner join arsnode n
        on s.pri_nid = n.nid
    inner join arsag ag
        on n.sid = ag.sid
        and ag.agid_name='$AGID_NAME'
where s.pri_nid between 2 and 10 and s.appl_id='T'
        union 
       select distinct left(doc_name, locate(trim(translate(doc_name,'','0123456789')), doc_name)-1)|| left(trim(translate(doc_name,'','0123456789')),3)||'1' as doc_name,lower(n.logon) as logon from $TABLE_NAME s
    inner join arsnode n
        on s.pri_nid = n.nid
    inner join arsag ag
        on n.sid = ag.sid
        and ag.agid_name='$AGID_NAME'
where s.pri_nid between 2 and 10 and s.appl_id='T') t 
on (sc.name = t.doc_name and sc.type = 'D') 
when not matched then 
  insert (name,node) values (t.doc_name,t.logon)
/;
  }

  # Commit 
  push @prt,'commit';
  
}
writeSQL(\@prt,$prev_agid_name);

