package BSE::TB::Image;
use strict;
# represents an image from the database
use Squirrel::Row;
use BSE::ThumbCommon;
use BSE::TB::TagOwner;
use vars qw/@ISA/;
@ISA = qw/Squirrel::Row BSE::ThumbCommon BSE::TB::TagOwner/;
use Carp qw(confess);

our $VERSION = "1.011";

=head1 NAME

BSE::TB::Image - images attached to an article or a global image.

=head1 SYNOPSIS

  my @images = $article->images;

=head1 DESCRIPTION

X<images>This class represents an image attached to an article, or a
global image.

=head1 METHODS

=over

=item id

Unique id for this image.

=item articleId

article this image belongs to.  C<-1> for global images.

=item image

image filename as stored in the images directory.  See C</image_url>
to get a URL to the image.

=item alt

alternate text for the image

=item width

=item height

X<image, width>X<image, height>width and height of the
image in pixels.

=item url

url to link to when the image is inlined.

=item displayOrder

sort key for ordering images belonging to an article (or within the
global image collection.)

=item name

unique name for the image within the images belonging to an article
(or withing the global image collection.)  Can be an empty string.

=item storage

the external storage used for the image, or C<local> for locally
stored images.

=item src

for externally stored images, the URL to the image.  Use
C</image_url()>.

=item ftype

the type of image, either C<img> for normal images, C<svg> for SVG
images or C<flash> for flash files.

=cut

sub columns {
  return qw/id articleId image alt width height url displayOrder name
            storage src ftype/;
}

sub table { "image" }

=item formatted(...)

Call the format() image handler object for this image.

Accepts the following parameters:

=over

=item *

C<align> - sets the align attribute.

=item *

C<extras> - extra C<img> tag attributes.

=back

Returns HTML.

=cut

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

=item inline(...)

Inline the image, accepts the following parameters:

=over

=item *

C<align> - set class to C<< bse_image_I<align> >>.

=back

Returns HTML.

=cut

sub inline {
  my ($self, %opts) = @_;

  my $cfg = delete $opts{cfg} || BSE::Cfg->single;

  my $handler = $self->_handler_object($cfg);

  return $handler->inline
    (
     image => $self,
     %opts,
    );
}

=item popimage(...)

Call the popimage() image handler object for this image, displaying
the image as a thumbnail that displays a larger version when clicked.

Parameters:

=over

=item *

C<class> - controls the section of the config file that popup
parameters are taken from.

=item *

C<static> - true to use static URLs for the thumbnails.

=back

Returns HTML.

=cut

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

=item image_url

Return the image's source URL.  This will be the storage URL if the
image is C<storage> is not C<local>.

=cut

sub image_url {
  my ($im) = @_;

  return $im->src || BSE::TB::Images->base_uri . $im->image;
}

=item json_data

Returns the image data as a data structure suitable for conversion to
JSON.

=cut

sub json_data {
  my ($self) = @_;

  my $data = $self->data_only;
  $data->{url} = $self->image_url;
  $data->{tags} = [ $self->tags ];

  return $data;
}

=item dynamic_thumb_url(...)

Return a dynamic URL to a thumbnail of the image.

Requires one named parameter:

=over

=item *

C<geo> - the thumbnail geometry to use.

=back

=cut

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

=item article

The article this image belongs to.

=cut

sub article {
  my ($self) = @_;

  if ($self->articleId == -1) {
    require BSE::TB::Site;
    return BSE::TB::Site->new;
  }
  else {
    require BSE::TB::Articles;
    return BSE::TB::Articles->getByPkey($self->articleId);
  }
}

=item remove

Remove the image.

=cut

sub remove {
  my ($self) = @_;

  $self->remove_tags;
  unlink $self->full_filename;
  return $self->SUPER::remove();
}

=item update

Make updates to the image.

=cut

sub update {
  my ($image, %opts) = @_;

  my $errors = delete $opts{errors}
    or confess "Missing errors parameter";

  my $actor = $opts{_actor}
    or confess "Missing _actor parameter";

  my $warnings = $opts{_warnings}
    or confess "Missing _warnings parameter";

  require BSE::CfgInfo;
  my $cfg = BSE::Cfg->single;
  my $image_dir = BSE::CfgInfo::cfg_image_dir($cfg);
  my $fh = $opts{fh};
  my $fh_field = "fh";
  my $delete_file;
  my $old_storage = $image->storage;
  my $filename;
  if ($fh) {
    $filename = $opts{display_name}
      or confess "Missing display_name";
  }
  elsif ($opts{file}) {
    unless (open $fh, "<", $opts{file}) {
      $errors->{filename} = "Cannot open $opts{file}: $!";
      return;
    }
    $fh_field = "file";
    $filename = $opts{file};
  }
  if ($fh) {
    local $SIG{__DIE__};
    eval {
      my $msg;
      require DevHelp::FileUpload;
      my ($image_name) = DevHelp::FileUpload->
	make_fh_copy($fh, $image_dir, $filename, \$msg)
	  or die "$msg\n";

      my $full_filename = "$image_dir/$image_name";
      require BSE::ImageSize;
      my ($width, $height, $type) = BSE::ImageSize::imgsize($full_filename);
      if ($width) {
	$delete_file = $image->image;
	$image->set_image($image_name);
	$image->set_width($width);
	$image->set_height($height);
	$image->set_storage("local");
	$image->set_src(BSE::TB::Images->base_uri . $image_name);
	$image->set_ftype(BSE::TB::Images->get_ftype($type));
      }
      else {
	die "$type\n";
      }

      1;
    } or do {
      chomp($errors->{$fh_field} = $@);
    };
  }

  my $name = $opts{name};
  if (defined $name) {
    unless ($name =~ /^[a-z_]\w*$/i) {
      $errors->{name} = "msg:bse/admin/edit/image/save/nameformat:$name";
    }
    if (!$errors->{name} && length $name && $name ne $image->name) {
      # check for a duplicate
      my @other_images = grep $_->id != $image->id, $image->article->images;
      if (grep $name eq $_->name, @other_images) {
	$errors->{name} = "msg:bse/admin/edit/image/save/namedup:$name";
      }
    }
  }

  if (defined $opts{alt}) {
    $image->set_alt($opts{alt});
  }

  if (defined $opts{url}) {
    $image->set_url($opts{url});
  }

  keys %$errors
    and return;

  my $new_storage = $opts{storage};
  defined $new_storage or $new_storage = $image->storage;
  $image->save;

  my $mgr = BSE::TB::Images->storage_manager;

  if ($delete_file) {
    if ($old_storage ne "local") {
      $mgr->unstore($delete_file);
    }
    unlink "$image_dir/$delete_file";

    $old_storage = "local";
  }

  # try to set the storage, this failing doesn't fail the save
  eval {
    $new_storage = 
      $mgr->select_store($image->image, $new_storage, $image);
    if ($image->storage ne $new_storage) {
      # handles both new images (which sets storage to local) and changing
      # the storage for old images
      $old_storage = $image->storage;
      my $src = $mgr->store($image->image, $new_storage, $image);
      $image->set_src($src);
      $image->set_storage($new_storage);
      $image->save;
    }
    1;
  } or do {
    my $msg = $@;
    chomp $msg;
    require BSE::TB::AuditLog;
    BSE::TB::AuditLog->log
      (
       component => "admin:edit:saveimage",
       level => "warning",
       object => $image,
       actor => $actor,
       msg => "Error saving image to storage $new_storage: $msg",
      );
    push @$warnings, "msg:bse/admin/edit/image/save/savetostore:$msg";
  };

  if ($image->storage ne $old_storage && $old_storage ne "local") {
    eval {
      $mgr->unstore($image->image, $old_storage);
      1;
    } or do {
      my $msg = $@;
      chomp $msg;
      require BSE::TB::AuditLog;
      BSE::TB::AuditLog->log
	(
	 component => "admin:edit:saveimage",
	 level => "warning",
	 object => $image,
	 actor => $actor,
	 msg => "Error saving image to storage $new_storage: $msg",
	);
      push @$warnings, "msg:bse/admin/edit/image/save/delfromstore:$msg";
    };
  }

  return 1;
}

sub tag_owner_type {
  "BI"
}

sub tableClass {
  "BSE::TB::Images";
}

1;

=back

=head1 INHERITED BEHAVIOUR

Inherits from L<BSE::TB::TagOwner> and L<BSE::ThumbCommon>

=head1 AUTHOR

Tony Cook <tony@develop-help.com>

=cut
