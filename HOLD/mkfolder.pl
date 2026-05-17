#!/ars/home/bin/perl -w
use File::Basename qw(fileparse);
use strict;


die "Usage: $0 mapping.csv\nmapping format: AGNAME,LDD,BCNR,KUNDENNR\nWill create/overwirte file mapping.xml\n" unless (scalar(@ARGV));

open(my $fin,'<',$ARGV[0]);
my ($filename, $dir, $suffix) = fileparse($ARGV[0], qr/\.[^.]*/);

my $template;
{
	local $/ = undef;
	$template = <DATA>;
};

open(my $fout,'>',$dir.$filename.'.xml')|| die "ERROR: open XML: $!";

# Print XML header
print $fout '<?xml version="1.0" encoding="UTF-8" ?>
<!-- 10.5.0.8 -->
<onDemand xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
  <folder name="',$filename,'" description="ERM Folder" displayDocHold="true" >',"\n";

while (<$fin>) {
	next if ($. < 2); # Skip header row
	chomp;
	s/\r//;
	s/\"//;

	my ($AGNAME,$LDD,$BCNR,$KUNDENNR) = split(/,/);

    my %vars = (
        AGNAME   => $AGNAME,
        LDD      => $LDD,
        BCNR     => $BCNR,
        KUNDENNR => $KUNDENNR
    );

	my $output = $template;
	$output =~ s/%(\w+)/$vars{$1}/ge;
	print $fout $output,"\n";

}

print $fout '      <field name="LDD" description="Event date" fieldType="Date" mappingType="Single" />
      <field name="BCNR" description="BCNR or NL" fieldType="String" mappingType="Single" />
      <field name="KUNDENNR" description="KONTONNR or KUNDENNUMER" fieldType="String" mappingType="Single" />
      <field name="AGNAME" fieldType="Application Group" mappingType="Single" />

      <permission group="*PUBLIC">
         <fieldInfo name="LDD" sortOrder="0" sortType="Ascending" between="true" equal="Default"  dateInterval="Last" dateIntLength="0" dateIntType="Days" dateDefaultFormat="%Y-%m-%d" dateDisplayFormat="%Y-%m-%d" queryOrder="1" displayOrder="1" />
         <fieldInfo name="BCNR" sortOrder="1" sortType="Ascending" between="false" equal="Default" greaterThan="false" gtOrEqual="false" in="true" lessThan="false" like="true" ltOrEqual="false" notBetween="false" notEqual="true" notIn="true" queryOrder="2" displayOrder="2" wildCard="Append" />
         <fieldInfo name="KUNDENNR" sortOrder="2" sortType="Ascending" between="false" equal="Default" greaterThan="false" gtOrEqual="false" in="true" lessThan="false" like="true" ltOrEqual="false" notBetween="false" notEqual="true" notIn="true" notLike="true" queryOrder="3" displayOrder="3" wildCard="Append" />
         <fieldInfo name="AGNAME" sortOrder="0" sortType="Ascending" between="false" equal="Default" queryOrder="4" displayOrder="4" />
      </permission>
   </folder>
</onDemand>',"\n";

close($fout);
close($fin);

__DATA__
	<applicationGroup name="%AGNAME" >
		<mapping fieldName="LDD" dbName="%LDD" />
		<mapping fieldName="BCNR" dbName="%BCNR" />
		<mapping fieldName="KUNDENNR" dbName="%KUNDENNR" />
	</applicationGroup>