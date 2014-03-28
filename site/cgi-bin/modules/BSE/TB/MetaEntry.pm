package BSE::TB::MetaEntry;
use strict;
use base 'Squirrel::Row';

our $VERSION = "1.002";

sub table {
  "bse_article_file_meta";
}

sub columns {
  qw/id file_id name content_type value appdata owner_type/;
}

sub defaults {
  content_type => "text/plain",
  appdata => 1,
}

sub is_text {
  $_[0]->content_type eq "text/plain"
}

sub is_text_type {
  $_[0]->content_type =~ m(^text/);
}

sub value_text {
  my ($self) = @_;

  $self->is_text_type or return;

  my $value = $self->value;
  utf8::decode($value) or return;

  return $value;
}

sub set_value_text {
  my ($self, $value) = @_;

  $self->is_text_type or return;

  utf8::encode($value);

  $self->set_value($value);

  1;
}

1;
