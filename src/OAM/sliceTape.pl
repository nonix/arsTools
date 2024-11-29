#!/usr/bin/perl -w
use File::Basename qw(basename);
use Fcntl 'SEEK_CUR';
use Convert::EBCDIC qw(ebcdic2ascii);
use strict;

die "Usage: $0 tape [data_dir]\n" unless (scalar(@ARGV));

my $tapeName = $ARGV[0];
my $dstDir = $ARGV[1];
$dstDir = './' unless (defined($dstDir));

die "ERROR: The destination directory not found!\n" unless (-d $dstDir);

open(my $tape, '<:raw', $tapeName) || die $!;

my $r;  # number of bytes read
while ($r = sysread($tape, my $buffer, 128)) {
	my($col44e, $obj44e, $fileSize, $blockSize) = unpack("a44a44Nx4Nx28", $buffer);

	my $collection = ebcdic2ascii($col44e);
	$collection =~ s/\s*$//;	# trim the trailing blanks
	my $workDir = $dstDir.'/'.$collection;
	mkdir $workDir unless (-d $workDir);	# Create the work dir unless exists 

	my $objName = ebcdic2ascii($obj44e);
	$objName =~ s/\s*$//;		# trim the trailing blanks
	
	warn 'DEBUG: ',join("\t", $collection, $objName, $fileSize, $blockSize),"\n" if ($ENV{DEBUG});
	
	# Now read/write the meat
	$buffer = undef;
	$r = sysread($tape, $buffer, $blockSize);
	die $! unless(defined($r));
	open(my $fh, '>>:raw', $workDir.'/'.$objName) || die $!;
	my $w = syswrite($fh, $buffer, $blockSize);
	die $! unless(defined($w));
	warn "WARN: Bytes written do not match bytes read. $w/$r\n" if( $w != $r );
	close($fh);
}

die $! unless(defined($r));
close($tape);
