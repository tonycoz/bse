package BSE::TB::Image;
use strict;
# represents an image from the database
use Squirrel::Row;
use BSE::ThumbCommon;
use vars qw/@ISA/;
@ISA = qw/Squirrel::Row BSE::ThumbCommon/;
use Carp qw(confess);

our $VERSION = "1.002";

sub columns {
  return qw/id articleId image alt width height url displayOrder name
            storage src ftype/;
}

sub formatted {
  my ($self, %opts) = @_;

  my $cfg = delete $opts{cfg}
    or confess "Missing cfg parameter";

  my $handler = $self->_handler_object($cfg);

  return $handler->format
    (
     image => $self,
     %opts,
    );
}

sub inline {
  my ($self, %opts) = @_;

  my $cfg = delete $opts{cfg}
    or confess "Missing cfg parameter";

  my $handler = $self->_handler_object($cfg);

  return $handler->inline
    (
     image => $self,
     %opts,
    );
}

sub popimage {
  my ($im, %opts) = @_;

  my $cfg = delete $opts{cfg}
    or confess "Missing cfg parameter";

  my $handler = $im->_handler_object($cfg);

  return $handler->popimage
    (
     image => $im,
     %opts,
    );
}

sub image_url {
  my ($im) = @_;

  $im->src || "/images/$im->{image}";
}

sub json_data {
  my ($self) = @_;

  my $data = $self->data_only;
  $data->{url} = $self->image_url;

  return $data;
}

sub dynamic_thumb_url {
  my ($self, %opts) = @_;

  my $geo = delete $opts{geo}
    or Carp::confess("missing geo option");

  return $self->thumb_base_url
    . "?g=$geo&page=$self->{articleId}&image=$self->{id}";
}

sub thumb_base_url {
  '/cgi-bin/thumb.pl';
}

sub full_filename {
  my ($self) = @_;

  return BSE::TB::Images->image_dir() . "/" . $self->image;
}

# compatibility with BSE::TB::File
sub filename {
  my ($self) = @_;

  return $self->image;
}

1;
