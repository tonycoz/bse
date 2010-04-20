#!/usr/bin/perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../cgi-bin/modules";
use BSE::API qw(bse_init bse_cfg);
use BSE::Cfg;
use Image::Size;
use Getopt::Long;

{
  bse_init("../cgi-bin");
  my $cfg = bse_cfg();

  my $geo_is_id;
  GetOptions(i => \$geo_is_id);

  my $geo = shift
    or usage("No geometry supplied");
  my $input = shift
    or usage("No input file supplied");
  my $output = shift;

  my $geo_string;
  if ($geo_is_id) {
    $geo_string = $cfg->entry("thumb geometries", $geo);
    $geo_string
      or usage("No [thumb geometries].$geo entry found");
  }
  else {
    $geo_string = $geo;
  }

  my $thumbs_class = $cfg->entry('editor', 'thumbs_class')
    or usage("No thumbnail engine configured");

  (my $thumbs_file = $thumbs_class . ".pm") =~ s!::!/!g;
  require $thumbs_file;
  my $thumbs = $thumbs_class->new($cfg);
  
  my ($width, $height, $type) = imgsize($input);
  defined $width
    or usage("Cannot parse input file: $type");
  
  my $error;
  $thumbs->validate_geometry($geo_string, \$error)
    or usage("Invalid geometry $geo_string: $error");

  my ($start_type) = $input =~ /\.(\w+)$/;
  my ($outwidth, $outheight, $outtype) =
    $thumbs->thumb_dimensions_sized($geo_string, $width, $height, $start_type);

  my ($data, $endtype) =
    $thumbs->thumb_data
      (
       filename => $input,
       geometry => $geo_string,
       error => \$error,
      )
	or usage("Cannot make thumb data: $error");
  
  if ($output) {
    open my $out_fh, ">", $output
      or die "Cannot create file $output: $!\n";
    binmode $out_fh;
    print $out_fh $data;
    close $out_fh;
  }
  else {
    my $insize = _commas(-s $input);
    my $outsize = _commas(length $data);
    print <<EOS;
Input: $width x $height (size: $insize, type: $start_type)
Calc dimensions: $outwidth x $outheight (type: $outtype)
Output: $outsize bytes (type: $endtype)
EOS
  }

  exit;
}

sub usage {
  my (@msg) = @_;
  die <<EOS;
@msg

Produce a thumb image to outputfilename (if supplied)
or image information to stdout otherwise.
Usage:
  $0 geostring inputfilename [outputfilename]
  $0 -i geoid inputfilename [outputfilename]
EOS
}

sub _commas {
  my $num = shift;
  1 while ($num =~ s/([0-9])([0-9]{3})\b/$1,$2/);

  return $num;
}
