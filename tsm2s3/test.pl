#!/ars/odadm/bin/perl -w
use DBI;
use Data::Dumper;
use strict;

my $DBUSER='odadm';
my $DBPASSWD='adm4archive';
my $TCPPORT='db2c_agarch';
my $DBCONNECT='DATABASE='.$ENV{DB2INSTANCE}.'; HOSTNAME=localhost; PORT='.$TCPPORT.'; PROTOCOL=TCPIP';

my $dh = DBI->connect('dbi:DB2:'.$DBCONNECT,$DBUSER,$DBPASSWD,{PrintError => 0, RaiseError => 1, ShowErrorStatement => 1, AutoCommit => 1, FetchHashKeyName => 'NAME_lc'});

my %a = @{$dh->selectcol_arrayref(qq/select type, count(distinct name)as count from SC_CCA group by type/,{ Columns=>[1,2] })};
print Dumper(\%a),"\n";

$dh->disconnect;