#!/ars/odadm/bin/perl -w
use DBI;
#use Data::Dumper;
use threads qw(yield);
use Thread::Queue;
use threads::shared;
use POSIX qw(strftime);
use strict;
  
my $DBUSER='odadm';
my $DBPASSWD='adm4archive';
my $TCPPORT='db2c_agarch';
my $DBCONNECT='DATABASE='.$ENV{DB2INSTANCE}.'; HOSTNAME=localhost; PORT='.$TCPPORT.'; PROTOCOL=TCPIP';
my $CMODAG='AKB-C35-EW-Stat-J-AIX';
my $CMODAPP='AKB-LY2110-TXT';
my $NTHREADS = 5;

#
# main()
#
my $ulock :shared;
my $STOP :shared = 0;

print 'INFO: ',scalar(localtime(time))," Reconciliation started ...\n";

my $arsag = get_arsag(shift);
# print Dumper($arsag),"\n";
# exit reconReport($arsag);

# trap Ctrl-C and enqueue exit ASAP
$SIG{INT} = sub { warn "WARN: Stop requested\n";$STOP=1 };

# Create db queues
my $q = Thread::Queue->new();
my $q2 = Thread::Queue->new();

# Start loader workers
my @dbl;
push @dbl,threads->create(\&dbloader) for (1..$NTHREADS);
sleep 1;

# enqueue all arsag at once
$q->enqueue(values(%$arsag));

# End dbl queue
$q->end();

# Start aws s3 workers
threads->create(\&S3lsProcessor) for (1..$NTHREADS);
sleep 1;

# Wait for dbloader to finish
$_->join() for (@dbl);

print "INFO: final wait ...\n";
# now end the S3 queue
$q2->end();

# Wait until all (S3) finished.
$_->join() for threads->list();

# Generate and archive the report
my $rc=-1;
$rc=reconReport($arsag) unless($STOP);

print 'INFO: ',scalar(localtime(time))," Reconciliation finished ...\n";
exit($rc);

# END

sub create_sc_table {
  my ($dh,$sctable) = @_;
  $dh->do(qq/
    create table $sctable (
      segment varchar(18) not null,
      name varchar(11) not null,
      type char(1) not null default 'D',
      lo int not null default 0,
      ins_rows int not null default 0,
      del_rows int not null default 0,
      status int not null default 0)      
  /);
  
  # Create the two indices
  $dh->do(qq/create index ${sctable}_IX1 on $sctable(name)/) ;
  $dh->do(qq/create index ${sctable}_IX2 on $sctable(segment)/) ;
}

sub load_sc_table {
  my ($agref) = @_;

  my $sctable = qq/SC_$agref->{agid_name}/;
  
  # Connect to the DB for this routine
  my $dh = DBI->connect('dbi:DB2:'.$DBCONNECT,$DBUSER,$DBPASSWD,{PrintError => 0, RaiseError => 1, ShowErrorStatement => 1, AutoCommit => 1, FetchHashKeyName => 'NAME_lc'});
  
  # drop corrupted tables (e.g. crashed while NOT LOGGED INITALLY)
  # -- not implemented yet :-) 
  # select TABNAME from TABLE(ADMIN_GET_TAB_INFO(null, null)) where AVAILABLE='N' and tabname like 'SC\_%' escape '\';
  # comment
  # Create SC_XXX if not exists
  create_sc_table($dh,$sctable) unless (table_exists($dh,$sctable));
  
  # Delete all disposed or migrated out segments
  $dh->do(qq/delete from $sctable where segment not in (select table_name from arsseg) or segment in (select table_name from arsseg where bitand(mask,8)>0)/);
  
  # Get all segments where number of rows changed
  my $arsseg = $dh->selectall_hashref(qq/select distinct table_name as segment, ins_rows, del_rows from arsseg where (table_name,ins_rows,del_rows) not in (select segment,ins_rows,del_rows from $sctable) and agid=? and bitand(mask,8)=0/,'segment',undef,$agref->{agid});
  
# print Dumper(\%arsseg),"\n";

  # At least one segment needs to be merged
  if (scalar(keys(%$arsseg))) {

    # Set LO flag when treating AG with Large Objects
    my $islo = '0';
    $islo = qq/int(decode(substring(doc_name,length(doc_name)),'\$',1,0))/ if ($agref->{islo});
    
    # Set SL flag when treating a SL table
    my $issl = '';
    $issl = qq/and appl_id='T'/ if ($agref->{agid_name} eq 'SL');
    
    # Begin Transaction  
    $dh->begin_work;
    
    # Activate not logged
    $dh->do(qq/alter table $sctable activate not logged initially/);
    
    # Merge-in all missing segments or oopen segments
    for my $segref (values(%$arsseg)) {
      last if ($STOP);
      
      {
        lock($ulock);
        print "INFO: Loading from $segref->{segment}\n";
      }
      # Remove all deleted rows
      $dh->do(qq/
          delete $sctable where rowid in (
          select s.rowid from $sctable s left outer join $segref->{segment} t
              on s.name=translate(t.doc_name,'','\$','')
          where s.segment=? and t.doc_name is null);
      /,undef,$segref->{segment});
      
      # Add new rows
      $dh->do(qq/
      merge into $sctable sc using (
        select distinct doc_name as name,'D' as type, $islo as lo from $segref->{segment} where pri_nid>100 $issl
          union
        select distinct varchar(resource) as name,'R' as type,0 as lo from $segref->{segment} where resource >0 and pri_nid>100 $issl) t
      on (sc.name=translate(t.name,'','\$','') and sc.segment=?)
      when not matched then 
        insert (segment,name,type,lo,ins_rows,del_rows) values (?,translate(t.name,'','\$',''),t.type,t.lo,?,?)/,
          undef,$segref->{segment},$segref->{segment},$segref->{ins_rows},$segref->{del_rows});
    }
    $dh->commit;
    
    # Update statistics using external script
    qx!/ars/odadm/bin/update_stats.sh $sctable!;
    my $rc=($?>>8);
    if ($rc) {
      warn "ERROR: update_stats.sh $sctable finished with RC=$rc\n";
    } elsif (-f qq/update_stats.$sctable.log/) {
      unlink qq/update_stats.$sctable.log/;
    }  
  }
  
  # Reset status in SC_XXX to enable search
  resetStatus($dh,$sctable);
  
  # If AG has large objects, make sure intermediate objects are inserted
  treatLO($dh,$agref) if($agref->{islo} && not($STOP));

  # get the distribution between Objects and Resources
  my %ret = @{$dh->selectcol_arrayref(qq/select type, count(distinct name)as count from $sctable group by type/,{ Columns=>[1,2] })};
  
  
  $dh->disconnect;
  
  return(defined($ret{D})?$ret{D}:0,defined($ret{R})?$ret{R}:0);
}  

sub resetStatus {
  my ($dh,$sctable)=@_;

  # Begin Transaction  
  $dh->begin_work;
  
  # Activate not logged
  $dh->do(qq/alter table $sctable activate not logged initially/);
  
  # Execute, to trick DB2 error SQL0513W use dummy where
  $dh->do(qq/update $sctable set status=0 where status=1/);
  
  # Commit
  $dh->commit;
}

sub treatLO {
  my($dh,$agref) = @_;

  # i.e.: 123FAAC$ must have 123FAAA$, 123FAAB$ and 123FAAA$
  my $sctable = qq/SC_$agref->{agid_name}/;
  my $s1 = $dh->prepare(qq/
      select segment,
      left(name,locate(trim(translate(name,'','0123456789')),name)-1)||left(trim(translate(name,'','0123456789')),3) as loadid,
      substring(trim(translate(name,'','0123456789')),4) as maxindex,
      ins_rows,del_rows from $sctable where lo>0 and name = (
        select max(name) as lastname from $sctable where lo>0 and name not like '\%A'
        group by left(name,locate(trim(translate(name,'','0123456789')),name)-1)||left(trim(translate(name,'','0123456789')),3)
        )
  /);
  $s1->execute;
  while (my $r = $s1->fetchrow_hashref) {
    
    # Iterate from A to maxindex
    # "A" .. reverse("CA")
    for my $i ('A' .. reverse($r->{maxindex})) {
      my $ri=scalar(reverse($i));
      last if ($ri eq $r->{maxindex}); # No need to merge the maxindex
      my $intername = qq/$r->{loadid}$ri/;
      $dh->do(qq/
        merge into $sctable sc using (select ? as segment,? as name from sysibm.sysdummy1) t on (sc.segment=t.segment and sc.name=t.name)
        when not matched then
          insert (segment,name,type,lo,ins_rows,del_rows) values (t.segment,t.name,'D',1,?,?)
      /,undef,$r->{segment},$intername,$r->{ins_rows},$r->{del_rows});
    }
  }
  $s1->finish;
}

# returns hashref to arsag
sub get_arsag {
  my ($subset) = @_;
  
  my $where = '';
  if (defined($subset)) {
    $where = 'and '.$subset;
  }
  my $dh = DBI->connect('dbi:DB2:'.$DBCONNECT,$DBUSER,$DBPASSWD,{PrintError => 0, RaiseError => 1, ShowErrorStatement => 1, AutoCommit => 1, FetchHashKeyName => 'NAME_lc'});

  my $arsag = $dh->selectall_hashref(qq/
    select agid,name as agname,agid_name,(select max(mod(comp_obj_size,1024)) from arsapp where agid=arsag.agid) as islo 
    from arsag 
    where agid in (select agid from arsseg where table_name in (select name from sysibm.systables)) $where
    order by agid_name
    /,'agid_name');

  $dh->disconnect;
  return($arsag);
}

# returns 0=not exists, 1=exists
sub table_exists {
  my ($dh,$table) = @_;

  my $res = $dh->selectrow_array(qq/select count(*) from sysibm.systables where name=?/,undef,$table);
  return($res);
}

sub dbloader {
  $|=1;
  while (my $agref = $q->dequeue) {

      my ($docCount,$resCount) = load_sc_table($agref);
      yield;
      last if ($STOP);
      enqueueS3ls($agref,$docCount,$resCount);
      yield;
      last if ($STOP);
  }
}

sub enqueueS3ls {
  my ($agref,$docs,$res) = @_;
  
  if ($docs+$res) {
    my $agid_name=$agref->{agid_name};
    
    if ($docs >10000) {
      # slplit into lower granularity if more docs
      for my $i (1..9) {
        $q2->enqueue(qq!$agid_name/$i!);
      }
      # enqueue resources only if exists
      $q2->enqueue(qq!$agid_name/RES/!) if ($res);
    } else {
      # This bundles both docs and res
      $q2->enqueue(qq!$agid_name/!);
    }
  }
}

sub S3lsProcessor {

  my $awsroot = uc($ENV{DB2INSTANCE});
  $awsroot = qq!aws s3 ls s3://p-ondemand/IBM/ONDEMAND/$awsroot/# --recursive 2>/dev/null!;
  
  my $dh = DBI->connect('dbi:DB2:'.$DBCONNECT,$DBUSER,$DBPASSWD,{PrintError => 1, RaiseError => 0, ShowErrorStatement => 1, AutoCommit => 1, FetchHashKeyName => 'NAME_lc'});
  
  $|=1;
  while (my $pattern = $q2->dequeue()) {
  
    # Pattern format: ABC/1 or ABC/ or ABC/RES
    my $sctable = (split(/\//,$pattern))[0];
    $sctable = qq/SC_$sctable/;
    
    my $awscmd = $awsroot;
    $awscmd =~ s/\#/$pattern/;
    
    {
      lock($ulock);
      print "INFO: S3 ls $pattern ...\n";
    }
    
    open(my $s3ls,'-|',$awscmd) || warn "ERROR: Unable to start process: $awscmd\n";
    
    my $uh = $dh->prepare(qq/update $sctable set status=1 where name=? and status=0/);
    while (my $obj = <$s3ls>) {
      chomp($obj);
      $uh->execute((split(/\//,$obj))[-1]);
      last if ($STOP);
    }
    $uh->finish;
    close($s3ls);
    last if ($STOP);
  }
  $dh->disconnect;
}

sub reconReport {
  my ($arsag) = @_;
  
  my $dh = DBI->connect('dbi:DB2:'.$DBCONNECT,$DBUSER,$DBPASSWD,{PrintError => 1, RaiseError => 0, ShowErrorStatement => 1, AutoCommit => 1, FetchHashKeyName => 'NAME_lc'});
  my @out;
  push @out, qq!Reconciliation report between\n       CMOD\{$ENV{DB2INSTANCE}\} and s3://p-ondemand as of: !.strftime("%F",localtime);
  push @out,'';
  push @out, 'Errors found:';
  my $c=0;
  for my $agref (values(%$arsag)) {
    my $sctable = qq/SC_$agref->{agid_name}/;
    my $sh = $dh->selectall_hashref(qq/select segment,type,count(distinct name) as count from $sctable where status=0 group by segment,type order by segment,type/,'segment');
    if (scalar(keys(%$sh))) {
      push @out, $agref->{agname};
      for (values(%$sh)) {
        push @out, qq/       $_->{segment}.$_->{type}: $_->{count}/;
        ++$c unless ($agref->{agid_name} eq 'SL');  # don't increase error counter for System Log
      }
      push @out, '';
    }
  }
  $dh->disconnect;
  
  # Finalize report
  push @out, '       NONE' unless($c);
  push @out, ('','List of application groups researched','-------------------------------------');
  push @out,$_->{agname} for (values(%$arsag));
  push @out, '*** End of report ***';
  
  # Write to the file
  open(my $fh,'>','recon.txt') || die "ERROR: Unable to open recon.txt\n";
  print $fh join("\n",@out),"\n";
  close($fh);
  
  # Write .IND
  open(my $ih,'>','recon.ind') || die "ERROR: Unable to open recon.ind\n";
  print $ih 'CODEPAGE:923',"\n";
  # NTBEE00 holds number of errors encountered
  print $ih 'GROUP_FIELD_NAME:NRBEE00',"\n";
  print $ih 'GROUP_FIELD_VALUE:',$c,"\n";
  print $ih 'GROUP_OFFSET:0',"\n";
  print $ih 'GROUP_LENGTH:0',"\n";
  print $ih 'GROUP_FILENAME:recon.txt',"\n";
  close($ih);
  
  unless ($ENV{DEBUG}) {
    # arsload would clean-up the report.* files
    my $out=qx!/opt/ondemand/bin/arsload -h $ENV{DB2INSTANCE} -u admin -g $CMODAG -a $CMODAPP -vf recon 2>&1!;
    $c += ($?>>8);
    print $out;
  }
  return($c);

}

