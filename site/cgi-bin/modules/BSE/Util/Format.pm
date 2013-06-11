package BSE::Util::Format;
use strict;

our $VERSION = "1.001";

=head1 NAME

BSE::Util::Format - formatting tools

=head1 SYNOPSIS

  # from perl
  use BSE::Util::Format;
  my $formatted = BSE::Util::Format::bse_numner($format, $value)

  # from templates
  <:number "money" [some value ] :>
  <:= bse.number("money", value) :>

=head1 FUNCTIONS

=over

=item bse_number(format, value, cfg)

Format a number per rules defined in the config file.

This uses configuration from section C<< [ number I<format>] >>, so
formatting for format C<money> is defined by section
C<<[number money]>>.

Configuration parameters:

=over

=item *

C<comma> - the string to use in adding comma separators to numbers.
Default: C<,>.

=item *

C<comma_limit> - numbers smaller than this are not commified.
Default: C<1000>.

=item *

C<commify> - set to 0 to disable commification.  Default: 1.

=item *

C<decimal> - decimal point.  Default: C<.>

=item *

C<divisor> - value to divide the value by before formatting.
eg. C<100> to express a number in cents in dollars.  Must be non-zero.
Default: 1.

=item *

C<places> - the number of decimal places to force after the decimal
point.  If negative the natural number of places are used.  Default: -1.

=back

=cut

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

=back

=head1 AUTHOR

Tony Cook <tony@develop-help.com>

=cut
