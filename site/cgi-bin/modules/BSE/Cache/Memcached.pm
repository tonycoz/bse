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
