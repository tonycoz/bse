package BSE::TB::SiteCommon;
use strict;
use Carp qw(confess);

our $VERSION = "1.022";

=head1 NAME

BSE::TB::SiteCommon - methods common to the site and article objects

=head1 SYNOPSIS

  my @steps = $article->set_parents;
  my @sections = $site->children;

=head1 DESCRIPTION

Provides methods common to the Article and BSE::TB::Site objects.

=head1 USEFUL METHODS

=over

=cut

sub step_parents {
  my ($self) = @_;

  BSE::TB::Articles->getSpecial('stepParents', $self->{id});
}

sub visible_step_parents {
  my ($self) = @_;

  my $now = now_sqldate();
  BSE::TB::Articles->getSpecial('visibleStepParents', $self->{id}, $now);
}

sub stepkids {
  my ($self) = @_;

  return BSE::TB::Articles->getSpecial('stepKids', $self->{id});
}

sub allstepkids {
  my ($self) = @_;

  return BSE::TB::Articles->getSpecial('stepKids', $self->{id});
}

sub visible_stepkids {
  my ($self) = @_;

  use BSE::Util::SQL qw/now_sqldate/;
  my $today = now_sqldate();

  if ($self->{generator} eq 'BSE::Generate::Catalog') {
    require BSE::TB::Products;

    return BSE::TB::Products->getSpecial('visibleStep', $self->{id}, $today);
  }
  else {
    return BSE::TB::Articles->getSpecial('visibleStepKids', $self->{id}, $today);
  }
  
  return ();
}

# returns a list of all children in the correct sort order
# this is a bit messy
sub allkids {
  my ($self) = @_;

  require BSE::TB::OtherParents;

  my @otherlinks = BSE::TB::OtherParents->getBy(parentId=>$self->{id});
  my @normalkids = BSE::TB::Articles->children($self->{id});
  my %order = (
	       (map { $_->{id}, $_->{displayOrder} } @normalkids ),
	       (map { $_->{childId}, $_->{parentDisplayOrder} } @otherlinks),
	      );
  my @stepkids = $self->allstepkids;
  my %kids = map { $_->{id}, $_ } @stepkids, @normalkids;

  return @kids{ sort { $order{$b} <=> $order{$a} } keys %kids };
}

# returns a list of all visible children in the correct sort order
# this is a bit messy
sub all_visible_kids {
  my ($self) = @_;

  BSE::TB::Articles->all_visible_kids($self->{id});
}

sub all_visible_kid_tags {
  my ($self) = @_;

  BSE::TB::Articles->all_visible_kid_tags($self->{id});
}

sub all_visible_products {
  my ($self) = @_;

  require BSE::TB::Products;
  BSE::TB::Products->all_visible_children($self->{id});
}

sub all_visible_product_tags {
  my ($self) = @_;

  require BSE::TB::Products;
  BSE::TB::Products->all_visible_product_tags($self->{id});
}

sub all_visible_catalogs {
  my ($self) = @_;

  return grep $_->{generator} eq "BSE::Generate::Catalog", $self->all_visible_kids;
}

sub visible_kids {
  my ($self) = @_;

  return BSE::TB::Articles->listedChildren($self->{id});
}

=item menu_kids

Returns a list of children meant to be listed in menus.

=cut

sub menu_kids {
  my ($self) = @_;

  return grep $_->listed_in_menu, $self->visible_kids;
}


=item all_menu_kids

Returns a list of allkids meant to be listed in menus.

=cut

sub all_menu_kids {
  my ($self) = @_;

  return grep $_->listed_in_menu, $self->all_visible_kids;
}

=item images

Return article images (or global images for the site).

=cut

sub images {
  my ($self) = @_;

  unless ($self->{_images}) {
    require BSE::TB::Images;
    $self->{_images} =
      [ 
       sort { $a->{displayOrder} <=> $b->{displayOrder} }
       BSE::TB::Images->getBy(articleId=>$self->{id})
      ];
  }

  return @{$self->{_images}};
}

=item image_tags

Image tag information within the current article.

=cut

sub image_tags {
  my ($self) = @_;

  require BSE::TB::Tags;
  require BSE::TB::TagMembers;
  return
    {
     tags => [ BSE::TB::Tags->getSpecial(images => $self->id) ],
     members => [ BSE::TB::TagMembers->getSpecial(images => $self->id) ],
    };
}

=item images_tagged

Return an arrayref of images for this article (or global images) that
have the specified tags.

In list context, return the result of collection_with_tags as the
second parameter.

=cut

sub images_tagged {
  my ($self, $tags) = @_;

  require BSE::TB::Images;
  my $result = BSE::TB::Images->collection_with_tags
    (
     "images",
     $tags,
     {
      self => $self,
     },
    );

  return $result->{objects} unless wantarray;
  return ( $result->{objects}, $result );
}

=item image_by_name

Return an image from the site or article given the image name.

=cut

sub image_by_name {
  my ($self, $name) = @_;

  unless ($self->{_images_by_name}) {
    $self->{_images_by_name} =
      +{
	map { lc $_->name => $_ } grep $_->name, $self->images
       };
  }

  my $image = $self->{_images_by_name}{lc $name}
    or return;

  return $image;
}

=item image_by_index

Return an image for an article (or the site) by index.

Named images are not counted and the index starts from 1.

=cut

sub image_by_index {
  my ($self, $index) = @_;

  unless ($self->{_images_by_index}) {
    $self->{_images_by_index} = [ grep !$_->name, $self->images ];
  }

  $index >= 1 && $index <= @{$self->{_images_by_index}}
    or return;

  return $self->{_images_by_index}[$index-1];
}

sub uncache_images {
  my ($self) = @_;

  delete @{$self}{qw/_images _images_by_name _images_by_index/};
}

sub children {
  my ($self) = @_;

  return sort { $b->{displayOrder} <=> $a->{displayOrder} } 
    BSE::TB::Articles->children($self->{id});
}

=item files

Return the files for the article.

This caches the file list.

=cut

sub files {
  my ($self) = @_;

  unless ($self->{_files}) {
    $self->{_files} = [ $self->_files ];
  }

  return @{$self->{_files}};
}

sub _files {
  my ($self) = @_;

  require BSE::TB::ArticleFiles;
  return BSE::TB::ArticleFiles->getBy(articleId=>$self->{id});
}

=item uncache_files

Remove the cached file list.

=cut

sub uncache_files {
  my ($self) = @_;

  delete $self->{_files};
}

=item file_by_name

Return the file with the given name, or nothing if there is no such
file.

=cut

sub file_by_name {
  my ($self, $name) = @_;

  my ($file) = grep $_->name eq $name, $self->files
    or return;

  return $file;
}

sub remove_images {
  my ($self, $cfg) = @_;

  $cfg ||= BSE::Cfg->single;
  $self->uncache_images;
  my @images = $self->images;
  my $mgr;
  require BSE::CfgInfo;
  my $imagedir = BSE::CfgInfo::cfg_image_dir($cfg);
  for my $image (@images) {
    if ($image->{storage} ne 'local') {
      unless ($mgr) {
	require BSE::StorageMgr::Images;
	$mgr = BSE::StorageMgr::Images->new(cfg => $cfg);
      }
      $mgr->unstore($image->{image}, $image->{storage});
    }

    $image->remove();
  }
  $self->uncache_images;
}

sub remove_files {
  my ($self, $cfg) = @_;

  $cfg ||= BSE::Cfg->single;
  my @files = $self->files;
  my $mgr;
  require BSE::CfgInfo;
  for my $file (@files) {
    if ($file->storage ne 'local') {
      unless ($mgr) {
	require BSE::StorageMgr::Files;
	$mgr = BSE::StorageMgr::Files->new(cfg => $cfg);
      }
      $mgr->unstore($file->filename, $file->storage);
    }

    $file->remove($cfg);
  }
  $self->uncache_files;
}

sub _copy_fh_to_fh {
  my ($in, $out) = @_;

  local $/ = \8192;
  while (my $data = <$in>) {
    print $out $data
      or return;
  }

  return 1;
}

=item add_file($cfg, %opts)

Add a file to the site or article.

Options:

=over

=item *

C<filename> - the name of the file to add.  This or C<file> is required.

If C<filename> is in the BSE download directory BSE will take
ownership of the file - you must not remove it.

=item *

C<file> - a file handle of the file to add.  This or C<filename> is
required.

=item *

C<displayName> - the display name of the file.  Required.
eg. C<"foo.txt">

=item *

C<contentType> - the content type of the file.  Guessed from
C<displayName> if not supplied.

=item *

C<name> - an identifier for the file.  Required for global files,
though that may change.  Must unique within global files or within the
article's files, depending where you're adding it.

=item *

C<store> - set to true to perform storage processing on the file.

=item *

C<storage> - the storage to store the file in if C<store> is true.  If
blank or empty BSE will select store based on the configured rules.

=back

dies with an error message on failure.

Returns a file object on success.

=cut

sub add_file {
  my ($self, $cfg, %opts) = @_;

  require BSE::TB::ArticleFiles;
  defined $opts{displayName} && $opts{displayName} =~ /\S/
    or die "displayName must be non-blank\n";
  
  unless ($opts{contentType}) {
    require BSE::Util::ContentType;
    $opts{contentType} = BSE::Util::ContentType::content_type($cfg, $opts{displayName});
  }

  my $src_filename = delete $opts{filename};
  my $file_dir = BSE::TB::ArticleFiles->download_path($cfg);
  my $filename;
  if ($src_filename) {
    if ($src_filename =~ /^\Q$file_dir\E/) {
      # created in the right place, use it
      $filename = $src_filename;
    }
    else {
      open my $in_fh, "<", $src_filename
	or die "Cannot open $src_filename: $!\n";
      binmode $in_fh;

      require DevHelp::FileUpload;
      my $msg;
      ($filename, my $out_fh) = DevHelp::FileUpload->
	make_img_filename($file_dir, $opts{displayName}, \$msg)
	  or die "$msg\n";
      _copy_fh_to_fh($in_fh, $out_fh)
	or die "Cannot copy file data to $filename: $!\n";
      close $out_fh
	or die "Cannot close output data: $!\n";
    }
  }
  elsif ($opts{file}) {
    my $file = delete $opts{file};
    UNIVERSAL::isa(\$file, "GLOB") || UNIVERSAL::isa($file, "GLOB")
	or die "file must be a file handle\n";
    my $out_fh;
    require DevHelp::FileUpload;
    my $msg;
    ($filename, $out_fh) = DevHelp::FileUpload->
	make_img_filename($file_dir, $opts{displayName}, \$msg)
	  or die "$msg\n";
    require File::Copy;
    _copy_fh_to_fh($file, $out_fh)
	or die "Cannot copy file data to $filename: $!\n";
    close $out_fh
      or die "Cannot close output data: $!\n";
  }
  else {
    die "No source file provided\n";
  }

  my $name = $opts{name};
  if (defined $name && $name =~ /\S/) {
    $name =~ /^\w+$/
      or die "name must be a single word\n";
    my ($other) = BSE::TB::ArticleFiles->getBy(articleId => $self->id,
					       name => $name)
      and die "Duplicate file name (identifier)\n";
  }

  require BSE::Util::SQL;
  my $fullpath = $file_dir . '/' . $filename;
  $opts{filename} = $filename;
  $opts{sizeInBytes} = -s $fullpath;
  $opts{displayOrder} = time;
  $opts{articleId} = $self->id;

  my $store = delete $opts{store};
  my $storage = delete $opts{storage} || '';

  my $fileobj = BSE::TB::ArticleFiles->make(%opts);
  $fileobj->set_handler($cfg);
  $fileobj->save;

  if ($store) {
    my $msg;
    eval {
      $self->apply_storage($cfg, $fileobj, $storage, \$msg);
    };
    $@ and $msg = $@;
    if ($msg) {
      if ($opts{msg}) {
	${$opts{msg}} = $msg;
      }
      else {
	$fileobj->remove($cfg);
	die $msg;
      }
    }
  }

  return $fileobj;
}

# only some files can be stored remotely
sub select_filestore {
  my ($self, $mgr, $file, $storage, $rmsg) = @_;

  my $store = $mgr->select_store($file->{filename}, $storage, $file);
  if ($store ne 'local') {
    if ($file->{forSale} || $file->{requireUser}) {
      $store = 'local';
      $$rmsg = "For sale or user required files can only be stored locally";
    }
    elsif ($file->{articleId} != -1 && $file->article->is_access_controlled) {
      $store = 'local';
      $$rmsg = "Files for access controlled articles can only be stored locally";
    }
  }

  return $store;
}

sub apply_storage {
  my ($self, $cfg, $file, $storage, $rmsg) = @_;

  $file
    or confess "Missing file option";
  $storage ||= '';
  my $mgr = BSE::TB::ArticleFiles->file_manager($cfg);
  $storage = $self->select_filestore($mgr, $file, $storage, $rmsg);
  $file->apply_storage($cfg, $mgr, $storage);
}

=item reorder_child($child_id, $after_id)

Change the order of children of $self so that $child_id is after
$after_id.

If $after_id is zero then $child_id becomes the first child.

=cut

sub reorder_child {
  my ($self, $child_id, $after_id) = @_;

  BSE::TB::Articles->reorder_child($self->{id}, $child_id, $after_id);
}

sub set_image_order {
  my ($self, $order, $images) = @_;

  $images ||= [ $self->images ];
  my %images = map { $_->{id} => $_ } @$images;

  my @new_order;
  for my $id (@$order) {
    if ($images{$id}) {
      push @new_order, delete $images{$id};
    }
  }
  for my $id (map $_->id, @$images) {
    if ($images{$id}) {
      push @new_order, delete $images{$id};
    }
  }

  my @display_order = map $_->{displayOrder}, @$images;
  my %seen;
  if (grep $seen{$_}++, @display_order) {
    # have a duplicate somewhere
    my ($max) = $display_order[0];
    @display_order = reverse( ($max - $#$images) .. $max );
  }
  for my $index (0 .. $#$images) {
    $new_order[$index]->set_displayOrder($display_order[$index]);
    $new_order[$index]->save;
  }

  return @new_order;
}

=item uncache

Clear any locally cached info.

=cut

sub uncache {
  my ($self) = @_;

  $self->uncache_images;
  $self->uncache_files;
}

1;

__END__

=back

=head1 AUTHOR

Tony Cook <tony@develop-help.com>

=cut
