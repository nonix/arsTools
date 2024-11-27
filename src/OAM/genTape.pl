#!/usr/bin/perl -w
use File::Basename qw(basename);
use Convert::EBCDIC qw(ascii2ebcdic);
use strict;

die "Usage: $0 tape srcDir\n" unless (scalar(@ARGV));

my $tapeName = $ARGV[0];
my $srcDir = $ARGV[1];
my $collection = basename($srcDir);

open(my $tape, '>:raw', $tapeName) || die $!;
foreach my $f (glob("$srcDir/*")) {
	print basename($f),"\n";
	my $objName = basename($f);
	my $objSize = -s $f;
	my $blockSize = 32624;
	open(my $fh, '<:raw', $f) || die $!;
	while (my $r = sysread($fh, my $buffer, $blockSize)) {
		print $tape ascii2ebcdic(sprintf("%-44s%-44s",$collection,$objName));
		print $tape pack('N3a4x24',$objSize,0,$r,ascii2ebcdic('*OAM'));
		print $tape pack('a*',$buffer);
	}
	close($fh);
}
close($tape);

