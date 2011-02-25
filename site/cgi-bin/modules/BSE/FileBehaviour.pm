package BSE::FileBehaviour;
use strict;

our $VERSION = "1.000";

sub new {
  my ($class, %opts) = @_;

  return bless \%opts, $class;
}

sub owner_id {
  my ($self, $owner) = @_;

  exists $self->{unowned}
    and return -1;

  return $owner->id;
}

sub unowned {
  my ($self) = @_;

  return $self->{unowned};
}

sub file_type {
  my ($self) = @_;

  # should have been passed to new()
  return $self->{file_type};
}

sub start_public {
  my ($self) = @_;

  # should have been passed to new()
  return $self->{public};
}

sub validate {
  return 1;
}

my %image_types =
  (
   GIF => "image/gif",
   JPG => "image/jpeg",
   XBM => "image/x-xbitmap",
   XPM => "image/x-xpm",
   PPM => "image/x-portable-anymap",
   PNG => "image/png",
   MNG => "video/x-mng",
   TIF => "image/tiff",
   BMP => "image/bmp",
   PSD => "image/x-psd",
   SWF => "application/x-shockwave-flash",
   CWS => "application/x-shockwave-flash",
   PCD => "image/pcd",
  );

sub populate {
  my ($self, $attr, $path) = @_;

  require Image::Size;
  my ($width, $height, $type) = Image::Size::imgsize($path);
  if ($width) {
    $attr->{width} = $width;
    $attr->{height} = $height;
    $attr->{content_type} = $image_types{$type} || "application/octet-stream";
  }
  else {
    require BSE::Util::ContentType;
    $attr->{content_type} = BSE::Util::ContentType::content_type(BSE::Cfg->single, $attr->{display_name});
  }

  return 1;
}

package BSE::FileBehaviour::Image;
use strict;

our @ISA = qw(BSE::FileBehaviour);

sub validate {
  my ($self, $attr, $rerror, $owner) = @_;

  unless ($attr->{content_type} =~ m(^image/)) {
    $$rerror = $self->image_file_message;
    return;
  }

  return 1;
}

sub image_file_message {
  my ($self) = @_;

  return $self->{image_file_message} || "msg:bse/files/image_file_required";
}

1;

=head1 HEAD

BSE::FileBehaviour - abstract base class for defining BSE::TB::File behaviour

=head1 DESCRIPTION

The following methods must be defined:

=over

=item *

file_url($file) - return a non-public URL to the file.

=item *

file_type - value to use for the file_type of files of this type

=item *

owner_id($owner) - used to extract the id of the owner object.  A
default implementation returns C<< $owner->id >>.

=item *

validate(\%object, \$error, $owner) - called to validate that the
file meets the needs of the owner.  A default implementation returns
true.

=back

=cut
