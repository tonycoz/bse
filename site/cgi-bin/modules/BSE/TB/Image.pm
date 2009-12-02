package BSE::TB::Image;
use strict;
# represents an image from the database
use Squirrel::Row;
use vars qw/@ISA/;
@ISA = qw/Squirrel::Row/;
use Carp qw(confess);
use DevHelp::HTML qw(escape_html);

sub columns {
  return qw/id articleId image alt width height url displayOrder name
            storage src ftype/;
}

sub _handler_object {
  my ($im, $cfg) = @_;

  my $module = "BSE::ImageHandler::" . ucfirst($im->ftype);
  (my $file = $module . ".pm") =~ s(::)(/)g;
  require $file;
  my $handler = $module->new(cfg => $cfg);
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

sub thumb {
  my ($im, %opts) = @_;

  my $cfg = delete $opts{cfg}
    or confess "Missing cfg parameter";

  my $handler = $im->_handler_object($cfg);

  return $handler->thumb
    (
     image => $im,
     %opts,
    );
}

sub image_url {
  my ($im, $cfg) = @_;

  $im->src || "/images/$im->{image}";
}

1;
