#!/ars/odadm/bin/perl -w
use Getopt::Long qw(GetOptions);
use Time::Local;
use Data::Dumper;
use XML::Simple;
use threads qw(yield);
use String::CRC32 qw(crc32);
use threads::shared;
use Thread::Queue;
use DBI;
use strict;

my $nthreads = 4;  # Maximum number of parallel threads to process SQLs
my $ret=0;
my $data_pos = tell(DATA)+9;
my @SQLQueue;
my %agrows :shared;

sub usage {
	die "Usage: $0 [-c] -x XML_feed1 [-r] [-x XML_feed2 [...]] [-l logFile] [-h]
--xmlin|x\t\tInput XML file
--reset|r\t\tReset scexpdate
--ignoreimplicit|c\tIgnore implicit rules
--log|l\t\t\tThe output log file
--help|h\t\tthis help
\n";
} #usage()

# XML file format:
#<?xml version='1.0' encoding='UTF-8'?>
#<ods:masterdata xmlns:ods="http://www.bank.ch/asb/masterdata/ondemand/saldierung">
#  <correlationId>002ac230-749b-4423-a729-14832017f995</correlationId>
#  <sourceSystem>UPSTREAM</sourceSystem>
#  <exportDate>2024-07-02T09:04:03.136Z</exportDate>
#  <data>
#    <object>
#      <objectType>BP</objectType>
#      <objectId>1446604</objectId>
#      <objectNum>12892457</objectNum>
#      <objectStr>1289.2457</objectStr>
#      <closeDate>2024-07-02</closeDate>
#    </object>
#  </data>
#</ods:masterdata>
#

sub getDATASection {
  my ($section) = @_;
  my $ret;
  
  seek(DATA, $data_pos, 0);
  OUTER: while (<DATA>) {
    chomp;
  next OUTER unless (/^\[$section\]\s*$/);
    INNER: while (<DATA>) {
      chomp;
      last OUTER if (/^\[.+?\]/); # exit on next section
      s/\-{2,}.*$//;  # remove -- in-line SQL comments
      next INNER if (/^\s*$/); # Skip blank lines
      $ret .= $_.' ';
    }
  }
  $ret =~ s/\/\*.*?\*\///g;  # remove /*SQL block comment*/
  $ret =~ s/\s*$//; # trim()
  $ret =~ s/^\s*//; # ltrim()
  $ret =~ s/\s{2,}/ /g; # squeez spaces
  die "ERROR: In getDATASection() \'$section\' was not found!\n" unless (length($ret));
  return($ret);
}

sub getRulesPredicates {
# Input: dh*
# Output: List of; AG.name, AG.agfield corresponding to resü. folder field, AG.formular field name.

	my ($dbh) = @_;
  
  my $sel = $dbh->prepare(getDATASection('RulesPredicates'));
  $sel->execute();
  my $ret = $sel->fetchall_arrayref({});
  $sel->finish;
  return($ret);
} #getFolderAG($dbh)

sub date2ars {
    my ($y,$m,$d)=split(q/-/,$_[0]);
    $m--;$y-=1900;
    return(int(timelocal(59,59,23,$d,$m,$y)/86400)+1);
}


sub execSQL {
  my $tid = threads->tid();
  my $dbh=DBI->connect('dbi:DB2:DATABASE='.$ENV{DB2INSTANCE}.'; HOSTNAME=localhost; PORT=db2c_'.lc($ENV{DB2INSTANCE}).'; PROTOCOL=TCPIP','odadm','adm4archiv',{ PrintError => 0, RaiseError => 1, ShowErrorStatement => 1 });
  my %res;
  while (my $l = $SQLQueue[$tid-1]->dequeue) {
    my ($agname,$sql,@param) = split(/#/,$l);
    # { lock($writelock);
      # warn "INFO[$tid]: SQL:\n$sql\nBIND:",scalar(@param),"\n",join(', ',@param),"\n";
    # }
    my $rows = $dbh->do($sql,undef,@param);
    $rows =~ s/0E0/0/;
    $res{$agname} += $rows;
	}
  
	$dbh->disconnect;
  
  # Upload results
  {
    lock(%agrows);
    $agrows{$_} = (defined($agrows{$_})?$agrows{$_}:0) + $res{$_} for (keys(%res));
  }
} # execSQL()


#main()

#Parse command line options
my %option;
my $log_fh = undef;

GetOptions(\%option,'reset|r','ignoreimplicit|c','xmlin|x','help|h','log|l=s') || usage();
usage if ($option{help} || !(defined($option{xmlin})|| defined($option{reset})));

if (defined($option{log})) {
	open($log_fh,'>>',$option{log}) || die "ERROR: unable to open log file: $option{log}\n";
    *STDOUT = $log_fh;
    *STDERR = $log_fh;
	$|=1;
}

warn 'INFO: stage1 started at ',scalar(localtime(time)),"\n";

# Open connection
my $dbh=DBI->connect('dbi:DB2:DATABASE='.$ENV{DB2INSTANCE}.'; HOSTNAME=localhost; PORT=db2c_'.$ENV{DB2INSTANCE}.'; PROTOCOL=TCPIP','odadm','adm4archiv',{ PrintError => 0, RaiseError => 1, ShowErrorStatement => 1 });
$|=1;

# Load input XML(s) to SCERMTMP table
if (defined($option{xmlin})) {
  # Truncate TMP table error when not present
  $dbh->do(qq/truncate table SCERMTMP immediate/);
  # prepare insert
  my $ins = $dbh->prepare(qq/insert into SCERMTMP (searchfld, searchval, scexpdate) values (?,?,?)/);
  my $rows = 0;
  print "Parsed values:\n" if (defined($option{log}));
  # process each XMLin file
  foreach my $xmlin (@ARGV) {
    # Parse input XML
    my $xml = XMLin($xmlin,GroupTags => {'data' => 'object'},KeyAttr => ['objectId'], ForceArray => ['object']);
    my $r = $xml->{data};
    
    # Prepare INSERT stmt for loading the XML.in to SCERMTMP table
    for my $i (keys(%$r)) {
      # Validation
      die "ERROR: Unknown object type (",$r->{$i}->{objectType},") in $xmlin\.\n" unless ($r->{$i}->{objectType} =~ /(Person|Position|BP)/);
      die "ERROR: Close date (",$r->{$i}->{closeDate},") invalid format. (ISO expected)\n" unless ($r->{$i}->{closeDate} =~ /\d{4}-\d{1,2}-\d{1,2}/);
      # this is just a hack to bypass non-complient data for Position
      if ($r->{$i}->{objectType} =~ /Position/) {
        if (ref($r->{$i}->{objectNum}) && ref($r->{$i}->{objectStr})) {
          $r->{$i}->{objectNum} = $i;
        }
      }
      die "ERROR: Empty (objStr|objNum) search value not allowed.\n" if (ref($r->{$i}->{objectNum}) && ref($r->{$i}->{objectStr}));
      # re-map keys from XML.in to respective Folder field names.
      $r->{$i}->{objectType} =~ s/Person/PersonNr/i;
      $r->{$i}->{objectType} =~ s/PosID/Position/i;
      my $num = (ref($r->{$i}->{objectNum})||length($r->{$i}->{objectNum})==0)?$r->{$i}->{objectStr}:$r->{$i}->{objectNum};
      # Execte insert
      print join(',',($xmlin,$r->{$i}->{objectType},$num,$r->{$i}->{closeDate})),"\n" if (defined($option{log}));
      $rows += $ins->execute($r->{$i}->{objectType},$num,date2ars($r->{$i}->{closeDate}));
    }
  }
  $ins->finish;
  warn "INFO: $rows row(s) inserted\n";
  # Update stats
  qx(/ars/odadm/bin/updateStats.sh SCERMTMP);
  
}

# Load all rules predicates into memory. (Note: it is not expected to be a lot)
my $RulesPredicates = getRulesPredicates($dbh);
# Reset scexpdate to 2059-01-01 for all involved tables
if ($option{reset}) {
  my %seen;
  foreach my $p (@$RulesPredicates) {
    $dbh->do(qq/update $p->{TABLE_NAME} set scexpdate=32508 where scexpdate!=32508/) unless ($seen{$p->{TABLE_NAME}});
    $seen{$p->{TABLE_NAME}} = 1;
  }
}

# Exit if reset only
exit unless (defined($option{xmlin}));

# Get unparsed queries
my $sqlUpdatebyTerminationRules = getDATASection('UpdatebyTerminationRules');
my $sqlUpdatebyTermination = getDATASection('UpdatebyTermination');
my $sqlUpdatebyCreation = getDATASection('UpdatebyCreation');

$dbh->disconnect;
my @SQLThreads;
for (1..$nthreads) {
  $SQLQueue[$_-1] = Thread::Queue->new(); # a bit of Russian roulette
  my $th = threads->create(\&execSQL); sleep 1;
  push @SQLThreads,$th;
}
sleep 1;

{
  my $i=0;  # table counter
  my %seen; # table register
  
  for my $p (@$RulesPredicates) {
     my $sql;
    if ($p->{BY_TERMINATION}) {
      if ($p->{FOLRULEFLD} eq '-') {
        # No Rules
        $sql = $sqlUpdatebyTermination;
      } else {
        $sql = $sqlUpdatebyTerminationRules;
        my $v = $p->{AGRULEFLD};
        $sql =~ s/\#AGRULEFLD/$v/g;
      }
      my $v = $p->{TABLE_NAME};
      $sql =~ s/\#TABLE_NAME/$v/g;
      $v = $p->{AGSEARCHFLD};
      $sql =~ s/\#AGSEARCHFLD/$v/g;
    } else { # BY_CREATION
      next if ($option{ignoreimplicit});
      $sql = $sqlUpdatebyCreation;
      my $v = $p->{TABLE_NAME};
      $sql =~ s/\#TABLE_NAME/$v/g;
      $v = $p->{AGRULEFLD};
      $sql =~ s/\#AGRULEFLD/$v/g;
    }
    my @param = ();
    while ($sql =~ s/\?(SEARCHFOL|FOLSEARCHFLD|FOLRULEFLD)\s/\? /) {
      push(@param,$p->{$1});
    }
    
    # Enqueue the SQL with Params
    $seen{$p->{TABLE_NAME}} = $i++ % $nthreads unless (defined($seen{$p->{TABLE_NAME}}));
    $SQLQueue[$seen{$p->{TABLE_NAME}}]->enqueue(join('#',$p->{AGNAME},$sql,@param));
      
  }
}
# Queue endpoints
$_->end() for (@SQLQueue);

# Wait until all finished.
$_->join() for @SQLThreads;

# Report rows updated per AG.
warn join(':',"INFO: $_",$agrows{$_}),"\n" foreach (sort(keys(%agrows)));

# Clean-up
END {
  warn 'INFO: stage1 finished at ',scalar(localtime(time)),"\n";
}
__END__
create table SCERMTMP (searchfld varchar(60) not null, searchval varchar(255) not null, scexpdate int not null);

__DATA__
[UpdatebyTermination]
update #TABLE_NAME s set scexpdate=(select distinct t.scexpdate from SCERMTMP t
                              where t.searchfld=?FOLSEARCHFLD /*q.FOLSEARCHFLD*/
                                and t.searchval=s.#AGSEARCHFLD /*q.agsearchfld*/)
where
 exists (select t.scexpdate from SCERMTMP t
                where t.searchfld=?FOLSEARCHFLD /*q.FOLSEARCHFLD*/
                  and t.searchval=s.#AGSEARCHFLD) /*q.agsearchfld*/

[UpdatebyTerminationRules]
update #TABLE_NAME s set scexpdate=(select distinct t.scexpdate from SCERMTMP t
                              where t.searchfld=?FOLSEARCHFLD /*q.FOLSEARCHFLD*/
                                and t.searchval=s.#AGSEARCHFLD /*q.agsearchfld*/) 
where
 exists (select t.scexpdate from SCERMTMP t
                where t.searchfld=?FOLSEARCHFLD /*q.FOLSEARCHFLD*/
                  and t.searchval=s.#AGSEARCHFLD) /*q.agsearchfld*/
 and s.#AGRULEFLD /*q.agrulefld*/
  in (select r.ruleval from SCEXPRULES r
        where r.searchfol=?SEARCHFOL /*q.searchfol*/
          and r.rulefld = ?FOLRULEFLD /*q.folrulefld*/
          and r.searchfld=?FOLSEARCHFLD /*q.folsearchfld*/
          and bitand(r.type,1) = 1)

[UpdatebyCreation]
update #TABLE_NAME s set scexpdate=1
where
 s.#AGRULEFLD /*q.agrulefld*/
  in (select r.ruleval from SCEXPRULES r
        where r.searchfol=?SEARCHFOL /*q.searchfol*/
          and r.rulefld = ?FOLRULEFLD /*q.folrulefld*/
          and bitand(r.type,1) = 0)

[RulesPredicates]
/*
bit mapped SCEXPRULES.Type
8,4,2,1 => Rules 0=use 1=ign,Search 0=use 1=ign,reserved,C/T [expl: 0 by Creation date;1 by Termination date];Note
------------------------------------------------------------------------------------
0,0,x,0   use,use,C;N/A if required use T and the feed should provide expDate set to 1970-01-01
0,0,x,1   use,use,T;most common case
0,1,x,0   use,ign,C;usable scenario, no need to provide Feed only rules are checked expDate set to 1970-01-01
0,1,x,1   use,ign,T;N/A as there is no feed of expDate to set to
1,0,x,0   ign,use,C;N/A if required use T and the feed should provide expDate set to 1970-01-01
1,0,x,1   ign,use,T;common case, when no rules are required, feed provides expDate
1,1,x,0   ign,ign,C;N/A do NOT set AG with "Implicit Hold"
1,1,x,1   ign,ign,T;N/A as there is no feed of expDate to set to
==============================================================================================================
== Usable cases re-ordered
==============================================================================================================
8,4,2,1 => Rules,Search,reserv.,C/T;Note
--------------------------------
0,0,x,1   1;use,use,T;most common case feed provides expDate joined with configured Rules
1,0,x,1   9;ign,use,T;common case, when no rules are required, feed provides expDate for matching documents
0,1,x,0   4;use,ign,C;usable scenario, no need to provide Feed data, all documents are checked for configured
                    Rules where matched expDate is set to 1970-01-01
*/
/* by Termination */
select distinct
  ag.name as agname,
  bitand(r.type,1) as by_Termination,
  r.searchfol,
  seg.table_name,
  r.searchfld as folsearchfld,
  saf.name as agsearchfld,
  r.rulefld as folrulefld,
  nvl(raf.name,'-') as agrulefld
from SCEXPRULES r
  inner join arsfol f   /*common to all*/
    on f.name = r.searchfol
    inner join arsfolfld sff  /*search related joins*/
      on sff.fid = f.fid
     and sff.name = r.searchfld
      inner join arsag2fol sa2f
        on sa2f.fid = f.fid
       and sa2f.folder_field = sff.field
      inner join arsagfld saf
        on saf.agid = sa2f.agid
        and saf.field = sa2f.appgrp_field1
    left outer join arsfolfld rff    /*rules related joins*/
      on  rff.fid = f.fid
     and rff.name = r.rulefld
      left outer join arsag2fol ra2f
        on ra2f.fid = rff.fid
       and ra2f.folder_field = rff.field
      left outer join arsagfld raf
        on raf.agid = ra2f.agid
        and raf.field = ra2f.appgrp_field1
  inner join arsseg seg
    on seg.agid = sa2f.agid
  inner join arsag ag
    on ag.agid = sa2f.agid
where bitand(r.type,1)=1  /* by Termination */
  and bitand(r.type,4)=0  /* must be searched i.e. stream data provided */
  /*filter out unwanted*/
  and ((r.rulefld != '-' and raf.name is not null) or (r.rulefld = '-' and raf.name is null))
union
/* by creation date */
select distinct
  ag.name as agname,
  bitand(r.type,1) as by_Termination,
  r.searchfol,
  seg.table_name,
  '-' as folsearchfld,
  '-' as agsearchfld,
  r.rulefld as folrulefld,
  raf.name as agrulefld
from SCEXPRULES r
  inner join arsfol f   /*common to all*/
    on f.name = r.searchfol
    inner join arsfolfld rff    /*rules related joins*/
      on  rff.fid = f.fid
     and rff.name = r.rulefld
      inner join arsag2fol ra2f
        on ra2f.fid = rff.fid
       and ra2f.folder_field = rff.field
      inner join arsagfld raf
        on raf.agid = ra2f.agid
        and raf.field = ra2f.appgrp_field1
  inner join arsseg seg
    on seg.agid = ra2f.agid
  inner join arsag ag
    on ag.agid = ra2f.agid
where bitand(r.type,1)=0  /* by Creation */
  and bitand(r.type,4)=4  /* ignore search */
  and bitand(r.type,8)=0  /* use rules */
order by 1,3,2
