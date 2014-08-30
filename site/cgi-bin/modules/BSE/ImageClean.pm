package BSE::ImageClean;
use strict;
use BSE::TB::Images;
use BSE::TB::Articles;
use BSE::TB::Files;
use BSE::CfgInfo qw(cfg_image_dir);
use File::Spec::Functions qw(catfile);

our $VERSION = "1.001";

sub scan {
  my ($class, $callback) = @_;

  my %articleIds = ( -1 => 1 );

  my %orphan_files;
  $callback->({type => "stage", stage => "images"});
  BSE::TB::Images->iterateBy
      (
       sub {
	 my ($image) = @_;

	 unless (exists $articleIds{$image->{articleId}}) {
	   $articleIds{$image->{articleId}} = 
	     defined(BSE::TB::Articles->getByPkey($image->{articleId}));
	 }
	 unless ($articleIds{$image->{articleId}}) {
	   $orphan_files{$image->image} = 1;
	   $callback->({type => "orphanimage", image => $image});
	 }
       },
      );

  my %names;
  $callback->({type => "endstage", stage => "images"});
  $callback->({type => "stage", stage => "index"});
  $callback->({type => "substage", stage => "index", substage => "images"});
  BSE::TB::Images->iterateBy
      (
       sub {
	 my ($image) = @_;
	 $names{$image->image} = $image->id;
       }
      );
  $callback->({type => "substage", stage => "index", substage => "thumbnails"});
  BSE::TB::Articles->iterateBy
    (
     sub {
       my ($article) = @_;
       $names{$article->thumbImage} = "a" . $article->id;
     },
     [ '<>', thumbImage => "" ]
    );

  my $image_dir = cfg_image_dir();
  my $pub_file_path = BSE::TB::Files->public_path;
  if ($image_dir eq $pub_file_path) {
    $callback->({type => "substage", stage => "index", substage => "publicfiles"});
    BSE::TB::Files->iterateBy
	(
	 sub {
	   my ($file) = @_;
	   $names{$file->filename} = "f" . $file->id;
	 },
	 [ '<>', is_public => 0 ],
	);
  }

  $callback->({type => "endstage", stage => "index"});
  $callback->({type => "stage", stage => "files"});

  if (opendir my $images, $image_dir) {
    while (defined(my $file = readdir $images)) {
      if ($file =~ /^\d{8}/) {
	unless ($names{$file} || !-f catfile($image_dir, $file)) {
	  $callback->({
		       type => "orphanfile",
		       file => $file,
		       fullfile => catfile($image_dir, $file),
		      });
	}
      }
    }
    closedir $images;
  }
  else {
    $callback->({type => "error", error => "Cannot open $image_dir: $!"});
  }
  $callback->({type => "endstage", stage => "files"});
}

1;

=head1 NAME

BSE::ImageClean - logic for finding orphan image files

=head1 SYNOPSIS

  use BSE::ImageClean;
  BSE::ImageClean->scan
    (
     sub {
       my ($type, @params) = @_;
       ...
     }
    );

=head1 DESCRIPTION

BSE::ImageClean provides the logic for scanning for orphanned image
files and image objects.

Call the F</scan> class method with a callback and act on the returned
values.

=head1 CALLBACK

The callback is called with a single parameter, a hashref containing
at least a C<type> key, depending on the value of type, other keys
will also be set:

=over

=item *

C<stage> - the stage of processing, The C<stage> key can be any of:

=over

=item *

C<images> - the images table is being scanned for orphan images

=item *

C<index> - the index of in-use image files in the images directory is
being built.

=item *

C<files> - the image file directory is being scanned for unused
images.  Only image files with 8 leading digits are included in the
scan.

=back

=item *

C<substage> - used during the C<index> stage, the C<substage> key
indicates scanning of the C<images> table, C<thumbnail>s in the
article table and public C<files> in the L<BSE::TB::Files> table.

=item *

C<endstage> - called at the end of a stage.  The C<stage> key contains
the key of the stage that's ending.

=item *

C<orphanimage> - an image object was found without an associated
article.  The C<image> key is the image object.  During final
processing the remove() method can be called on the image.

=item *

C<orphanfile> - a file that doesn't belong to an unorphaned image, an
aarticle thumbnail or as a public managed file was found.  The other
keys that are set are:

=over

=item *

C<file> - the base filename,

=item *

C<fullfile> - the full path to the file

=back

During final processing it's important that files belonging to orphans
are only removed if the orphan image object is.

=item *

C<error> - an error occurred.  The C<error> key is the error message.

=back

=head1 AUTHOR

Tony Cook <tony@develop-help.com>

=cut
