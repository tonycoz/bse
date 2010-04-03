package BSE::Cache::Cache;
use strict;

# BSE cache interface for Cache interface compatible caches.

sub new {
  my ($class, $cfg) = @_;

  my $cache_class = $cfg->entry("cache", "cache_class");
  ( my $cache_mod_file = $cache_class . ".pm" ) =~ s(::)(/)g;

  require $cache_mod_file;

  my $params_str = $cfg->entry("cache", "params");
  my @eval_res = eval $params_str;
  if ($@) {
    print STDERR "Error evaluating cache parameters: $@\n";
    return;
  }
  my $cache = $cache_class->new(@eval_res);

  my $self = bless { cache => $cache }, $class;
}

sub set {
  my ($self, $key, $value) = @_;

  my $entry = $self->{cache}->entry($key);
  $entry->freeze($value);
}

sub get {
  my ($self, $key) = @_;

  my $entry = $self->{cache}->entry($key);
  $entry->exists
    or return;

  return $entry->thaw;
}

sub delete {
  my ($self, $key) = @_;

  my $entry = $self->{cache}->entry($key);
  $entry->remove;
}

1;

