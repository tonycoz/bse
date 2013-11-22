package BSE::TB::Image;
use strict;
# represents an image from the database
use Squirrel::Row;
use BSE::ThumbCommon;
use BSE::TB::TagOwner;
use vars qw/@ISA/;
@ISA = qw/Squirrel::Row BSE::ThumbCommon BSE::TB::TagOwner/;
use Carp qw(confess);

our $VERSION = "1.007";

sub columns {
  return qw/id articleId image alt width height url displayOrder name
            storage src ftype/;
}

sub table { "image" }

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

  return $im->src || BSE::TB::Images->base_uri . $im->image;
}

sub json_data {
  my ($self) = @_;

  my $data = $self->data_only;
  $data->{url} = $self->image_url;
  $data->{tags} = [ $self->tags ];

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

sub article {
  my ($self) = @_;

  if ($self->articleId == -1) {
    require BSE::TB::Site;
    return BSE::TB::Site->new;
  }
  else {
    require Articles;
    return Articles->getByPkey($self->articleId);
  }
}

sub remove {
  my ($self) = @_;

  $self->remove_tags;
  unlink $self->full_filename;
  return $self->SUPER::remove();
}

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
      require Image::Size;
      my ($width, $height, $type) = Image::Size::imgsize($full_filename);
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
