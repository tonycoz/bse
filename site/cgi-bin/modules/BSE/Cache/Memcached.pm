package BSE::Cache::Memcached;
use strict;
use Cache::Memcached::Fast;

sub new {
  my ($class, $cfg) = @_;

  my $servers = $cfg->entry("cache", "servers");
  my @servers = split /;/, $servers;
  for my $server (@servers) {
    if ($server =~ /^\{(.*)\}$/) {
      my %server;
      my @entries = split /,/, $1;
      for my $entry (@entries) {
	if ($entry =~ /^(\w+)=(.*)$/) {
	  $server{$1} = $2;
	}
	else {
	  die "Invalid cache server entry $entry";
	}
      }
    }
  }
  my %params =
    (
     servers => \@servers,
    );
  for my $key (qw/namespace compress_threshold compress_ratio nowait max_size/) {
    my $value = $cfg->entry("cache", "mc_$key");
    defined $value and $params{$key} = $value;
  }

  my $cache = Cache::Memcached::Fast->new(%params);

  return bless
    {
     cache => $cache
    }, $class;
}

sub set {
  my ($self, $key, $value) = @_;

  $self->{cache}->set($key, $value);
}

sub get {
  my ($self, $key) = @_;

  return $self->{cache}->get($key);
}

sub delete {
  my ($self, $key) = @_;

  $self->{cache}->delete($key);
}

1;

=head1 NAME

BSE::Cache::Memcached - BSE interface to Cache::Memcached::Fast

=head1 SYNOPSIS

  [cache]
  class=BSE::Cache::Memcached::Fast
  servers=127.0.0.1:11211;{address=host:port,weight=0.5,noreply=1}
  ...

=head1 DESCRIPTION

Cache in one or more memcached instances.

Configurable [cache] values:

=over

=item *

servers - the servers to cache at (required).  Multiple servers can be
specified as a ; separated list.  Each entry is either a host:port or
a {} surrounded list of comma separated key=value, where address is a
required key.  See the Cache::Memcached::Fast documentation for
servers key information.

=item *

namespace, compress_threshold, compress_ratio, nowait, max_size - see
the Cache::Memcached::Fast documentation.

=back

=cut
