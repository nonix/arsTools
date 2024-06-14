#!/usr/bin/env perl

use strict;
use warnings;

use DBI;
use Config::IniFiles;

use File::Find qq(find);
use Cwd qq(abs_path);
use File::Basename qw(basename dirname);

my $config=Config::IniFiles->new( -file => dirname($0).'/config.ini', -fallback => 'all');
if (@Config::IniFiles::errors) {
  print "ERROR: ",@Config::IniFiles::errors,"\n";
  die "Problem with config.ini, please check\n";
}

# 1. all found in cache/migr
# 2. Check if linked file exists -l => -f 
# 3. set MIG_AGID_NAME.status=1
# 4. Report errors, when status=0

my $CACHEDIR = $config->val('all', 'CMOD_CACHE_DIR_TARGET');


die "Usage: $0 AGID_NAME\n" unless (scalar(@ARGV));
print "INFO: $0 $ARGV[0] Started at ",scalar(localtime(time)),"\n";
warn "WARN: Only DOC links are checked, RES are silently skipped.\n";
my $AGID_NAME=uc(shift);

my $dh = DBI->connect('dbi:DB2:DATABASE='.$config->val('all', 'DB2_INSTANCE').'; HOSTNAME='.$config->val('all', 'DB2_HOSTNAME').'; PORT='.$config->val('all', 'DB2_PORT').'; PROTOCOL=TCPIP',$config->val('all', 'DB2_USER'),$config->val('all', 'DB2_PWD'),
  {PrintError => 0, RaiseError => 1, ShowErrorStatement => 1, AutoCommit => 1, FetchHashKeyName => 'NAME_lc'});
my $sh = $dh->prepare(qq/update MIG_$AGID_NAME set status=1 where (doc_name=? or doc_name=?) and status=0/);

my $c=0;
for (qx(ls -1 $CACHEDIR/retr/$AGID_NAME/DOC)) {
  chomp;
  next if (/1$/||/^0$/||/^\s*$/);
  my $rv = $sh->execute($_,$_.'$');
    $c += $rv;
}
$sh->finish;
$dh->disconnect;
print "INFO: $c row(s) affected in MIG_$AGID_NAME\n";
print "INFO: $0 Finished at ",scalar(localtime(time)),"\n";
