package BSE::TB::Tag;
use strict;
use base 'Squirrel::Row';

our $VERSION = "1.002";

sub columns {
  qw(id owner_type cat val);
}

sub table { 'bse_tags' }

sub set_name {
  my ($self, $name) = @_;

  my ($cat, $val) = BSE::TB::Tags->split_name($name);
  $self->set_cat($cat);
  $self->set_val($val);
}

sub name {
  my ($self) = @_;

  my $cat = $self->cat;
  return length $cat ? "$cat: " . $self->val : $self->val;
}

sub canon_name {
  my ($self) = @_;

  return lc $self->name;
}

sub eq_name {
  my ($self, $name) = @_;

  my $error;
  my ($canon) = BSE::TB::Tags->canon_name($name, \$error)
    or return;

  return $canon eq $self->canon_name;
}

sub remove {
  my ($self) = @_;

  BSE::DB->single->run("BSE::TB::TagMembers.deleteTag" => $self->id);

  $self->SUPER::remove();
}

sub json_data {
  my ($self) = @_;

  my $data = $self->data_only;
  $data->{name} = $self->name;

  return $data;
}

1;
