package BSE::Cache;
use strict;

our $VERSION = "1.000";

sub load {
  my ($class, $cfg) = @_;

  $cfg ||= BSE::Cfg->single;
  my $cache_class = $cfg->entry("cache", "class");
  defined $cache_class
    or return;
  ( my $cache_mod_file = $cache_class . ".pm" ) =~ s(::)(/)g;
  require $cache_mod_file;
  return $cache_class->new($cfg);
}

1;
__END__
=head1 NAME

BSE::Cache - internal BSE cache module interface

=head1 SYNOPSIS

  my $cache = BSE::Cache::module->new($cfg);
  $cache->set($key, $complex_value);
  my $complex_value = $cache->get($key);
  $cache->delete($key)

=head1 DESCRIPTION

CPAN has Cache and Cache::Cache and CHI based caching, and some
library specific interfaces.

This library wraps all the confusion in yet another layer.

=head1 INTERFACE

=over

=item $class->new($cfg)

Create a new BSE::Cache compatible object.  Any parameters should be
loaded from the BSE configuration.

=item $obj->set($key, $complex_value)

Sets the given key to $complex_value, which may be a reference to a
hash or a hash of hashes, etc.

=item $obj->get($key)

Retrieves the value stored for $key.

Returns nothing if no cached value is found.

=item $obj->delete($key)

Delete the value stored for $key.  Returns nothing in particular.

=cut

=cut


