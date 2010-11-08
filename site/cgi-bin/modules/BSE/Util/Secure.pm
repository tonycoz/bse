package BSE::Util::Secure;
use strict;

our $VERSION = "1.000";

use vars qw(@ISA @EXPORT_OK);

@ISA = qw(Exporter);
@EXPORT_OK = qw(make_secret);
require 'Exporter.pm';

=head1 NAME

  BSE::Util::Secure - utilities that have something to do with security

=head1 SYNOPSIS

  use BSE::Util::Secure qw/make_secret/;
  my $secret = make_secret($cfg)

=head1 DESCRIPTION

Just tools used for security purposes.  Or something like that.

=over

=item make_secret($cfg)

Make a random 'secret', which can be used for a variety of purposes.

Uses some source of entropy where possible.

=cut

my $sequence = 0;

sub make_secret {
  my ($cfg) = @_;

  my $randompath = $cfg->entry('basic', 'randomdata');
  if ($randompath && open RANDDATA, "< $randompath") {
    my $data;
    read RANDDATA, $data, 16;
    close RANDDATA;
    if (length($data) == 16) {
      return unpack("H*", $data);
    }
  }

  # oh well, try it the other way
  use Digest::MD5 'md5_hex';
  my $result = md5_hex($sequence.time().rand().{}.$$);
  $sequence .= rand;

  return $result;
}

1;

=head1 AUTHOR

Tony Cook <tony@develop-help.com>

=cut
