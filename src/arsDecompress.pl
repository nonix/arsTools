#!/ars/odadm/bin/perl -w
use Compress::Raw::Zlib;
use strict;

my $x = new Compress::Raw::Zlib::Inflate()
   or die "Cannot create a inflation stream\n" ;

my $input = '' ;
binmode STDIN;
binmode STDOUT;

my ($output, $status) ;
while (read(STDIN, $input, 4096))
{
    $status = $x->inflate($input, $output) ;

    print $output ;

    last if $status != Z_OK ;
}

die "inflation failed\n"
    unless $status == Z_STREAM_END ;
