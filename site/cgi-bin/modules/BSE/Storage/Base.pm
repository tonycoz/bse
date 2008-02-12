package BSE::Storage::Base;
use strict;
use Carp qw(confess);

sub new {
  my ($class, %opts) = @_;

  defined $opts{cfg} and $opts{cfg}->can('entry')
    or confess "Missing or invalid cfg option";

  defined $opts{name} and $opts{name} =~ /^\w+$/
    or confess "Missing or invalid storage name";

  return bless \%opts, $class;
}

sub cfg {
  $_[0]{cfg};
}

sub name {
  $_[0]{name};
}

sub description {
  my $self = shift;

  $self->configure('description', $self->name);
}

sub section {
  my $self = shift;

  "storage " . $self->name;
}

sub configure {
  my ($self, $key, $default) = @_;

  return $self->cfg->entry($self->section, $key, $default);
}

sub match_file {
  my ($self, $pathname, $filename, $object) = @_;

  my $cond = $self->configure('cond');
  defined $cond
    or return 1;

  my $result = eval <<EOS;
stat \$pathname; # put stat values into _
return $cond;
EOS
  $@ and die $@;

  return $result;
}

1;

=head1 NAME

BSE::Storage::Base - base class for all storages

=head1 SYNOPSIS

  package BSE::Storage::Foo;
  use base 'BSE::Storage::Base';
  ...

  # somewhere else
  require BSE::Storage::Foo;
  my $store = BSE::Storage::Foo->new(cfg => $cfg, name => $name);

=head1 DESCRIPTION

This will provide default implementations where necessary.

=head1 AUTHOR

Tony Cook <tony@develop-help.com>

=cut
