#!/ars/odadm/bin/perl -w
use strict;

die "Usage: $0 doc_name.xxx\$ doc_len\n" unless (scalar(@ARGV));

my $LOfile = shift;
my $dirSize = shift;
my ($load_id, $doc_suffix);
my $LOsize=(-s $LOfile);

# An input file name shoudl start with segment name i.e. 123FAAE.xxxx
if ($LOfile =~ /^(\d+\D{3})(\D+)\.?/) {
  $load_id = $1;
  $doc_suffix = $2;
}
open(my $f,'<:raw',$LOfile)||die $!;
sysread($f,my $buf,$dirSize);
close($f);

# Initialize vars
my ($pages,$segSize,$comp_off) = unpack('x8 N3',$buf);
my $nextSegment;
my $bufOffset = 8 + 4*3; # 8 bytes preamble + 3x integer

warn 'Total pages:',$pages,"\n";
warn 'pages per segment:',$segSize,"\n";

my @res; # Holds results
while (1) {
  my ($comp_len,$segment) = unpack("x$bufOffset N w/a",$buf);
  if ($segment) {
    $comp_off = 0 if ($nextSegment); # Reset comp_off only after the first segment
    $nextSegment = $segment;
    $bufOffset += length($segment); # add actual string length
  }
  last unless ($comp_len);
  push @res,'arsadmin decompress -b '.$comp_off.' -l '.$comp_len.' -s '.$load_id.$nextSegment.' -o '.$load_id.$nextSegment.'.'.$comp_off;
  $comp_off += $comp_len;
  $bufOffset += 4 + 1; # 1 integer + 1byte of string len
};
print join("\n",@res),"\n";



