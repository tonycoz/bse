package BSE::URL;
use strict;

our $VERSION = "1.000";

sub rewrite_url {
  my ($self, $cfg, $url) = @_;

  my %replace = $cfg->entries("link replacement");
  for my $key (sort keys %replace) {
    my ($from, $to) = split /;/, $replace{$key};
    $url =~ s/^\Q$from/$to/i
      and last;
  }

  return $url;
}

1;
