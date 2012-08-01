package BSE::Console;
use strict;
use BSE::API qw(bse_init);

our $VERSION = "1.000";

sub new {
  my ($class, %opts) = @_;

  $opts{cgidir} ||= "../cgi-bin";

  bse_init($opts{cgidir});

  return bless \%opts, $class;
}

sub language {
  my $self = shift;

  $ENV{LANG} and return $ENV{LANG};

  $ENV{LC_ALL} and return $ENV{LC_ALL};

  return $self->cfg->entry("basic", "language_code", "en");
}

sub cfg {
  return BSE::API::bse_cfg();
}

=item message_catalog

Retrieve the message catalog.

=cut

sub message_catalog {
  my ($self) = @_;

  unless ($self->{message_catalog}) {
    require BSE::Message;
    my %opts;
    $self->_cache_available and $opts{cache} = $self->_cache_object;
    $self->{message_catalog} = BSE::Message->new(%opts);
  }

  return $self->{message_catalog};
}

sub _cache_available {
  my ($self) = @_;

  unless (defined $self->{_cache_available}) {
    my $cache_class = $self->cfg->entry("cache", "class");
    $self->{_cache_available} = defined $cache_class;
  }

  return $self->{_cache_available};
}

sub _cache_object {
  my ($self) = @_;

  $self->_cache_available or return;
  $self->{_cache} and return $self->{_cache};

  require BSE::Cache;

  $self->{_cache} = BSE::Cache->load($self->cfg);

  return $self->{_cache};
}

sub catmsg {
  my ($self, $id, $params, $default, $lang) = @_;

  defined $lang or $lang = $self->language;
  defined $params or $params = [];

  $id =~ s/^msg://
    or return "* bad message id - missing leading msg: *";

  my $result = $self->message_catalog->text($lang, $id, $params, $default);
  unless ($result) {
    $result = "Unknown message id $id";
  }

  return $result;
}

1;

=head1 NAME

BSE::Console - utilities for BSE console apps.

=head1 SYNOPSIS

=cut
