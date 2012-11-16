package BSE::Util::Format;
use strict;

our $VERSION = "1.000";

sub bse_number {
  my ($format, $value, $cfg) = @_;

  $cfg ||= BSE::Cfg->single;
  my $section = "number $format";
  my $comma_sep = $cfg->entry($section, "comma", ",");
  $comma_sep =~ s/^"(.*)"$/$1/;
  $comma_sep =~ /\w/ and return "* comma cannot be a word character *";
  my $comma_limit = $cfg->entry($section, "comma_limit", 1000);
  my $commify = $cfg->entry($section, "commify", 1);
  my $dec_sep = $cfg->entry($section, "decimal", ".");
  my $div = $cfg->entry($section, "divisor", 1)
    or return "* divisor must be non-zero *";
  my $places = $cfg->entry($section, "places", -1);

  my $div_value = $value / $div;
  my $formatted = $places < 0 ? $div_value : sprintf("%.*f", $places, $div_value);

  my ($int, $frac) = split /\./, $formatted;
  if ($commify && $int >= $comma_limit) {
    1 while $int =~ s/([0-9])([0-9][0-9][0-9]\b)/$1$comma_sep$2/;
  }

  if (defined $frac) {
    return $int . $dec_sep . $frac;
  }
  else {
    return $int;
  }
}

1;
