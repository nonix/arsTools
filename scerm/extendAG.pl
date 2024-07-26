#!/ars/odadm/bin/perl -w
use Text::CSV;
use strict;

die "Usage: $0 appAG.list\nlist is UTF-8 CSV format: app,ag\nNote: Ordered by ag\n" unless (scalar(@ARGV));

sub outputXML {
  my ($fn,$ag_r,$ap_r) = @_;
  
  # $fn hold ag name, need to remove umlauts, spaces, slashes
  $fn =~ s/ö/o/g;$fn =~ s/[\s\/\|,]/_/g;
  $fn =~ s/\s+$//;$fn .= '.xml';
  print $fn,"\n";
  open(my $fh,'>',$fn)||die "$!";
  binmode($fh, ":utf8");

  # Print intro
  print $fh '<?xml version="1.0" encoding="UTF-8" ?>',"\n",
  '<onDemand xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="/opt/ondemand/xml/ondemand.xsd">',"\n";
  
  print $fh join("\n",@$ag_r),"\n",join("\n",@$ap_r),"\n";
  print $fh '</onDemand>',"\n";
  
  close($fh);
  @$ag_r=();
  @$ap_r=();
}

# Load template from __DATA__
my %template;
{
  my $key = 'AG';
  while (<DATA>) {
  chomp;
    $key = 'APP' if (/^<application\s+/);
    push @{$template{$key}},$_;
  }
}

# Loop through AG list
my $prevag = "";
my @AG;
my @APP;

my ($ag,$app);
my $csv = Text::CSV->new ({ binary => 1, auto_diag => 1, comment_str => '#' });
open my $fh, "<:encoding(utf8)", $ARGV[0] or die "$ARGV[0]: $!";

$csv->bind_columns (\$app, \$ag);
while ($csv->getline ($fh)) {
  unless ($ag && $app) {
    warn "ERROR: Corrupted list file at line: $.\n";
    next;
  }
  warn "DEBUG: APP:$app,AG:$ag,PREVAG:$prevag\n";
  if ($ag ne $prevag) {
      outputXML($prevag,\@AG,\@APP) if ($prevag);
      $prevag = $ag;
  }

  unless (scalar(@AG)) {
    push @AG, "\n<!-- $ag -->";
    foreach my $i (@{$template{AG}}) {
      my $l = $i;
      $l =~ s/NN1AG/$ag/g;
      push @AG, $l;
    }
  }

  foreach my $i (@{$template{APP}}) {
    my $l = $i;
    # warn "DEBUG[before]: $l\n";
    $l =~ s/NN1AG/$ag/g;
    $l =~ s/NN1APP/$app/g;
    # warn "DEBUG[after]: $l\n";
    push @APP,$l;
  }
  
}
outputXML($ag,\@AG,\@APP) if (scalar(@AG));

__DATA__
<applicationGroup name="NN1AG"  enhancedRetManagement="true" >
	<field name="schold" type="Filter" dataType="Small Int" lockdown="true" updateable="true" />
	<field name="scexpdate" type="Filter" dataType="Date" updateable="true" />
	<permission user="ADMIN" adminAuthority="true" lvAuthority="true" accessAuthority="true" docViewPerm="true" docAddPerm="true" 
		docUpdatePerm="true" docDeletePerm="true" docPrintPerm="true" docCopyPerm="true" docHoldPerm="true" docCFSODPerm="true" 
		docFTIPerm="false" annotViewPerm="true" annotAddPerm="true" annotDeletePerm="false" annotUpdatePerm="false" annotCopyPerm="true" />
</applicationGroup>
<application name="NN1APP" appGroup="NN1AG">
	<preprocessParm dbName="scexpdate" defaultValue="2059-01-01" format="%Y-%m-%d" />
</application>