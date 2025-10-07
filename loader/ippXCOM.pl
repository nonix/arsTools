#!/ars/home/bin/perl -w
use Data::Dumper;
use XML::Simple qw(:strict);
use strict;

die "Usage: $0 file1.xcom [file2.xcom [...]]\n" unless (scalar(@ARGV));

sub writeIndex;

foreach my $xin (@ARGV) {
	open(my $xcom,'<',$xin)||die "ERROR: $!";
	my ($prolog, $has_prolog);
	my ($header, $has_header);
	my $buf = '';
	while (my $l = <$xcom>) {

		unless($has_prolog) {
			if ($l =~ /<Prolog>/i) {
				$buf = $l;
				
				# Trim the rest
				$buf =~ s/<\/Prolog>.*$/<\/Prolog>/;
			}
			$buf .= $l;
			if ($l =~ /<\/Prolog>/i) {
				$buf =~ s/(<\/Prolog>).*$/$1/is;
				# Parse Prolog
				$prolog = XMLin($buf);
				$has_prolog = 1;
			}
			next unless ($has_prolog);
			# I Have prolog, check the rest
		}
		
		if ($l =~ /<?xml.+?<ArchiveObject>/ims) {
			# Calculate offset of ArchiveObject in the file
			$offset = tell($xcom);
			$offset -= length($l) + index($l,'<?xml');
		}
		
		# Process Header
		unless ($has_header) {
			if ($l =~ /<Header>/i) {
				$buf = $l;
				$buf =~ s/^.*?(<Header>)/$1/i;
			}
			$buf .= $l;
			if ($l =~ /<\/Header>/i) {
				$buf =~ s/(<\/Header>).*$/$1/i;
				$header = XMLin($buf);
				$has_header = 1;
			}
			next unless ($has_header);
		}
		
		if ($l =~ /<\/ArchiveObject>/) {
			$length = tell($xcom) - $offset;
			$length -= length($l) + index(lc($l),'</archiveobject>') + 16;
			writeIndex($xin,$offset,$length,$prolog,$header);
			$buf = '';
			$has_header = 0;
		}
	}
	close($xcom);
}

sub writeIndex {
	my ($fileName,$offset,$length,$prolog,$header) = @_;
	warn 'DEBUG[prolog]:',Dumper($prolog),"\n";
	warn 'DEBUG[header]:',Dumper($header),"\n";
}