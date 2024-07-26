#!/ars/odadm/bin/perl -w
use Data::Dumper;
use POSIX qw(strftime);
use File::Basename qw(basename);
use threads qw(yield);
use threads::shared;
use Thread::Queue;
use Text::CSV qw(csv);
use DBI;
use IO::Handle;
use strict;

# Usage: $0 erm_folder [report_name (default: $0.$erm_folder.today().csv)]
# respective folder *MUST* contain following fields:
#     PERSONNR  BP  KONTONR FORMULAR  DATUM
# "AGNAME"	"AGID"	"SEGMENT"	"AFNAME"	"FFNAME"	"IS_ERM"	"EXPDATE"
# "-C0-10-EBES PLR-Rel1.0"	5618	"CFA3"	"bpNumber"	"BP"	"Yes"	16249
# "-C0-10-EBES PLR-Rel1.0"	5618	"CFA3"	"scandatum"	"Datum"	"Yes"	16249
# "-C0-10-EBES PLR-Rel1.0"	5618	"CFA3"	"formular"	"Formular"	"Yes"	16249
# "-C0-10-EBES PLR-Rel1.0"	5618	"CFA3"	"accNumber"	"KontoNr"	"Yes"	16249
# "-C0-10-EBES PLR-Rel1.0"	5618	"CFA3"	"person_nr"	"PersonNr"	"Yes"	16249
# "-C0-10-EBES PLR-Rel1.0 old"	5491	"AEA1"	"bpNumber"	"BP"	"Yes"	16249
# "-C0-10-EBES PLR-Rel1.0 old"	5491	"AEA1"	"scandatum"	"Datum"	"Yes"	16249
# "-C0-10-EBES PLR-Rel1.0 old"	5491	"AEA1"	"formular"	"Formular"	"Yes"	16249
# "-C0-10-EBES PLR-Rel1.0 old"	5491	"AEA1"	"accNumber"	"KontoNr"	"Yes"	16249
# "-C0-10-EBES PLR-Rel1.0 old"	5491	"AEA1"	"person_nr"	"PersonNr"	"Yes"	16249

die "Usage: $0 erm_folder [report_name]\n" unless (scalar(@ARGV));
my ($ERM_FOLDER, $RPT_NAME)=@ARGV;

my $NTHREADS = 24;
my @connection = ('dbi:DB2:DATABASE='.$ENV{DB2INSTANCE}.'; HOSTNAME=localhost; PORT=db2c_'.$ENV{DB2INSTANCE}.'; PROTOCOL=TCPIP','odadm',
                  'adm4archiv',{ PrintError => 0, RaiseError => 1, ShowErrorStatement => 1 });

# Hash containing the metadata organized by segment table
#   $qr{segment}->{agname}='-C0-10-EBES PLR-Rel1.0 old';
#                 ->{cols}->{BP}='bpNumber';
#                         ->{PERSONNR}='person_nr';
#                 ->{agid}=5491;
#                 ->{exdate}=16249; # 2014-06-27
#
my %qr;

# Metadata organized by agid
#   $qi{agid}-[0]='CFA1';
#   $qi{agid}-[1]='CFA2';
my %qi;

# Open connection
my $dbh=DBI->connect(@connection);
my $sh = $dbh->prepare(qq/
select distinct ag.name as agname,ag.agid,seg.table_name as segment,af.name as afname,upper(ff.name) as ffname, bitand(ag.type,16384) as is_ERM, days(current date) +1 -days('1970-01-01') -ag.db_exp_date as expdate
from arsfol f
    inner join arsfolfld ff
        on f.fid = ff.fid
        and upper(ff.name) in ('PERSONNR','BP','KONTONR','FORMULAR','DATUM')
    inner join arsag2fol a2f
        on a2f.fid = ff.fid
        and a2f.folder_field = ff.field
    inner join arsag ag
        on a2f.agid=ag.agid
    inner join arsagfld af
        on a2f.agid=af.agid
        and a2f.appgrp_field1 = af.field
    inner join arsseg seg
        on seg.agid = ag.agid
where upper(f.name)=upper(?)
order by 1,3,5
/);
$sh->execute($ERM_FOLDER);
while (my $r = $sh->fetchrow_hashref("NAME_lc")) {
  unless(defined($qr{$r->{segment}})) {
    my $s = $r->{segment};
    $dbh->do(qq/create tablespace ODADM_SCERM_$s/);
    # Fill %qr
    $qr{$s}->{agid}=$r->{agid};
    $qr{$s}->{expdate}=$r->{expdate};
    $qr{$s}->{is_erm}=$r->{is_erm};
    # Fill %qi
    push @{$qi{$r->{agid}}->{segment}},$s;
    $qi{$r->{agid}}->{agname} = $r->{agname};
    $s =~ s/^(\D+).+$/SCERM_$1/;
    $qi{$r->{agid}}->{scerm} = uc($s);
  }
  my $t = $qr{$r->{segment}};
  $t->{cols}->{$r->{ffname}} = $r->{afname};
}
$sh->finish();
$dbh->disconnect();

# build SCERMn by segment
sub buildSCERM;
warn "INFO: Building parcial ERM segment tables ...\n";
my $q = Thread::Queue->new(keys(%qr));
$q->end();

# Start workers for buildSCERM
threads->create(\&buildSCERM) for (1..$NTHREADS);
$_->join() for (threads->list());

# merge segment SCERMn to resulting SCERM
sub mergeSCERM;
warn "INFO: Merging parcial ERM segment tables ...\n";
$q = Thread::Queue->new(keys(%qi));
$q->end();

# Start workers for mergeSCERM
threads->create(\&mergeSCERM) for (1..$NTHREADS);
$_->join() for (threads->list());

warn "INFO: Generating ERM report ...\n";
# Generate report (.csv)
$RPT_NAME=join('.',basename($0,'.pl'),$ERM_FOLDER,strftime("%Y%m%d",localtime(time)),'csv');
$dbh=DBI->connect(@connection);
 open(my $fh,'>',$RPT_NAME)||die $RPT_NAME,$!;
 my $csv = Text::CSV->new ({binary => 1,eol => "\n" });
 $csv->say($fh,[qw/AGNAME PERSONNR BP KONTONR FORMULAR DATUM IS_LOCKED ANZAHL/]);

for my $agid (sort({$a <=> $b} keys(%qi))) {
  my $sh = $dbh->prepare(qq/select (select name from arsag where agid=?) as agname,personnr,bp,kontonr,formular,date(days('1970-01-01')-1+datum),is_locked,records as anzahl from $qi{$agid}->{scerm} t order by 1,2,3,4/);
  $sh->execute($agid);
  while (my $r = $sh->fetch) {
    map {s/\s+$//} @$r;
    $csv->say($fh,$r);
  }
  $sh->finish;
  my $sql = qq/drop table $qi{$agid}->{scerm}/;
  $dbh->do($sql);
}

close($fh);
$dbh->disconnect;
warn 'INFO: report is ready in: ',$RPT_NAME,"\n";

# The END
exit;

sub mergeSCERM {
  my $tid = threads->tid();
  my $dbh=DBI->connect(@connection);
  while (my $agid = $q->dequeue()) {
    my $SCERM = $qi{$agid}->{scerm};
    for my $odsegment (@{$qi{$agid}->{segment}}) {
      my $segment = 'SCERM_'.uc($odsegment);
      unless (pop @{$dbh->selectcol_arrayref(qq/select count(*) from sysibm.systables where name=?/,undef,$SCERM)}) {
        my $sql = qq/create table $SCERM   (PERSONNR	bigint not null default 0,
                                            BP	BIGINT not null default 0,
                                            KONTONR	BIGINT not null default 0,
                                            FORMULAR	varchar(125) not null default '-',
                                            DATUM	SMALLINT not null,
                                            IS_LOCKED char(1) not null default 'N',
                                            RECORDS	bigint not null)/;
        $dbh->do($sql);
      }
      my @cols = @{$dbh->selectcol_arrayref(qq/select name from sysibm.syscolumns where tbname=? order by name/,undef,$segment)};
      
      my $sql = qq/merge into $SCERM as r using (select /;
      $sql .= join(', ',@cols); # comma delimited list of cols: bp, kontonr, personnr, formular, datum, is_locked, records
      $sql .= ' from '.$segment.') as t on (';
      $sql .= join(' and ',map({"r.$_ = t.$_"} grep(!/datum|records/,@cols))).') when matched then update set ';
      $sql .= 'records = r.records+t.records, datum = decode(r.datum<t.datum, true, t.datum, r.datum) when not matched then insert (';
      $sql .= join(', ',@cols).') values ('.join(', ',map({"t.$_"} @cols)).')';
      my $rows = $dbh->do($sql);
      $rows = 0 if ($rows eq '0E0');
      warn "INFO[$tid]: $rows row(s) from $segment merged into $SCERM\n";
      $dbh->do(qq/drop tablespace ODADM_$segment/);
      $dbh->do(qq/commit/);
      yield();
    }
  }
  $dbh->disconnect();
}

sub buildSCERM {
  my $tid = threads->tid();
  my $dbh=DBI->connect(@connection);
  while (my $segment = $q->dequeue()) {
    my $SCERM = 'SCERM_'.$segment;
    # drop first if exists
    if (pop @{$dbh->selectcol_arrayref(qq/select count(*) from sysibm.systables where name=?/,undef,$SCERM)}) {
      my $sql = qq/drop tablespace ODADM_$SCERM/;
      $dbh->do($sql);
    }
    
    my $sql = qq/select /;
    my ($cols,$expdate,$is_erm) = @{$qr{$segment}}{qw/cols expdate is_erm/};
    my @group;
    foreach my $col (sort(keys(%$cols))) {
      if ($col eq 'DATUM') {
        $sql .= "max($cols->{$col}) DATUM, ";
      } else {
        $sql .= "$cols->{$col} $col, ";
        push @group, $cols->{$col};
      }
    }
    $sql .= q/decode(schold,0,'N','Y') as is_locked, / if ($is_erm);
    $sql .= 'count(*) records from '.$segment.' where '.$cols->{DATUM}.' <= '.$expdate;
    $sql .= ' and schold=0' if ($is_erm);
    $sql .= ' group by '.join(',',@group);
    $sql .= q/, decode(schold,0,'N','Y')/  if ($is_erm);
    warn "DEBUG: $sql\n";
    my $sql_ct = qq/create table $SCERM as ($sql) with no data in ODADM_$SCERM/;
    $dbh->do($sql_ct);
    
    $dbh->begin_work;
    $dbh->do(qq/alter table $SCERM activate not logged initially/);
    $dbh->do(qq/insert into $SCERM $sql/);
    $dbh->commit;
    yield();
  }
  $dbh->disconnect();
}
