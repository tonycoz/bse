package BSE::FileHandler::Base;
use strict;
use Carp qw(confess);

sub new {
  my ($class, $cfg) = @_;

  $cfg
    or confess "Missing cfg option";

  return bless
    {
     cfg => $cfg,
    }, $class;
}

sub cfg {
  $_[0]{cfg};
}

sub cfg_entry {
  my ($self, $key, $def) = @_;

  return $self->cfg->entry($self->section, $key, $def);
}

sub process_file {
  my ($self, $file) = @_;

  my $class = ref $self;
  confess "$class hasn't implemented process-file";
}

1;
