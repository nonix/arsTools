#!/ars/odadm/bin/perl -w
use DBI;
use Getopt::Long;
use File::Basename qw(basename dirname);
use Data::Dumper;
use strict;

my ($DB2USER,$DB2PASSWD,$DB2NAME,$DB2PORT) = ($ENV{DB2USER},$ENV{DB2PASSWD},$ENV{DB2NAME},$ENV{DB2PORT});

sub usage {
  warn 'Usage: ',basename($0),' -a name {-x|-v|-p} [-u fileName|-o fileName] [-h]',"\n";
  warn q/-a, --application='Name'   Application name (required)/,"\n";
  warn q(-x, --indexer               Get/Set indexer clob),"\n";
  warn q(-v, --fixed_view            Get/Set fixed_view clob),"\n";
  warn q(-p, --preprocessor          Get/Set preprocessor clob),"\n";
  warn q(-u, --update='file name'  Update / set clob with provided file),"\n";
  warn q(-o, --output='file name'  Get clob to file instead of STDOUT),"\n";
  warn q(-h, --help                  This text),"\n";
  
  warn 'Env.: DB2USER,DB2PASSWD,DB2NAME,DB2PORT,DB2INSTANCE',"\n";
  return 1;
} #usage()

my %opt;

GetOptions(\%opt,'application|a=s','indexer|x','fixed_view|v','preprocessor|p','update|u=s','output|o=s') || exit usage();
exit usage() if($opt{help} || !defined($opt{application}) ||
  ((defined($opt{indexer})?1:0) + (defined($opt{fixed_view})?1:0) + (defined($opt{preprocessor})?1:0) != 1) ||
  (defined($opt{update}) && defined($opt{output})));

$DB2USER='odadm'  unless (defined($DB2USER));
$DB2PASSWD='adm4archiv' unless (defined($DB2PASSWD));
$DB2NAME=$ENV{DB2INSTANCE} unless (defined($DB2NAME));
$DB2PORT='db2c_'.lc($ENV{DB2INSTANCE}) unless (defined($DB2PORT));

# Get clob column from options
my $clob;
for (qw(indexer fixed_view preprocessor)) {
	$clob=$_ if (defined($opt{$_}));
}

# Open in/out file handle
my $fh;
if (defined($opt{update})) {
	open($fh,'<',$opt{update}) || die "ERROR: Unable to open $opt{update}. $!\n";
} elsif (defined($opt{output})) {
	open($fh,'>',$opt{output}) || die "ERROR: Unable to open $opt{output}. $!\n";
} else {
	$fh = \*STDOUT;
}

my $dh = DBI->connect("dbi:DB2:DATABASE=$DB2NAME; HOSTNAME=localhost; PORT=$DB2PORT; PROTOCOL=TCPIP",$DB2USER,$DB2PASSWD,{ PrintError => 0, RaiseError => 1, ShowErrorStatement => 1 }) || die DBI->errstr;

if (defined($opt{update})) {
	# Slurp the file to $content
	my $content;
	{
		local $/;
		$content=<$fh>;
	}
	# Update respective $clob with $content
	my $rv = $dh->do(qq/update arsapp set $clob=?, upd_date=86400*(DAYS(CURRENT TIMESTAMP)-DAYS('1970-01-01'))+ MIDNIGHT_SECONDS(CURRENT TIMESTAMP),
						upd_dt=CURRENT TIMESTAMP where lower(name)=?/,undef,$content,lc($opt{application}));
	print "INFO: $rv row(s) affected.\n";
} else {
	# Select respective CLOB
	print $fh $dh->selectrow_array(qq/select $clob from arsapp where lower(name)=?/,undef,lc($opt{application}));
}

# Close what's open
END {
	$dh->disconnect if (defined($dh));
	close ($fh) if (defined($opt{update}) || defined($opt{output}) && defined($fh));
}
