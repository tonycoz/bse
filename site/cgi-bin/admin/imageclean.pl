#!/usr/bin/perl -w
use strict;
use FindBin;
use lib "$FindBin::Bin/../modules";
use BSE::API qw(bse_init);
use BSE::TB::Images;
use Articles;
use BSE::CfgInfo qw(cfg_image_dir);
use File::Spec::Functions qw(catfile);

bse_init("..");

my %articleIds = ( -1 => 1 );
my $images = BSE::TB::Images->new;
my @images = $images->all;

++$|;
print <<EOS;
Content-Type: text/plain

Image Cleanup Tool
------------------

Removing image records that have no article
EOS

# first remove any image records that don't have a valid article id
for my $image (@images) {
  print ".";
  # do we know about this article id?
  unless (exists $articleIds{$image->{articleId}}) {
    $articleIds{$image->{articleId}} = 
      defined(Articles->getByPkey($image->{articleId}));
  }
  unless ($articleIds{$image->{articleId}}) {
    $image->remove();
    print "x";
  }
}

print "\n\nRebuilding image list and indexing\n";
# rebuild the images list
$images = BSE::TB::Images->new;
@images= $images->all;

my %names = map { $_->{image}, $_->{id} } @images;

print "\n\nScanning for thumbnails\n";

my @articleids = Articles->allids;
for my $id (@articleids) {
  my $article = Articles->getByPkey($id)
    or next;
  if ($article->{thumbImage}) {
    $names{$article->{thumbImage}} = "a$id";
  }
}

print "\nRemoving unused images\n";

my $image_dir = cfg_image_dir();
opendir IMG, $image_dir
  or do { print "Cannot open $image_dir: $!\n"; exit };
while (defined(my $file = readdir IMG)) {
  if ($file =~ /^\d{8}/) {
    print ".";
    unless ($names{$file} || !-f catfile($image_dir, $file)) {
      print "x";

      unlink catfile($image_dir, $file)
	or print "\nCould not remove $image_dir$file: $!\n";
    }
  }
}

print "\nDone\n";

__END__

=head1 NAME

imageclean.pl - clean up the images directory and image records

=head1 SYNOPSIS

 (called as a CGI script, no values passed in)

=head1 WARNING

This will remove B<any> images in the configured managed images
directory that have names starting with 8 or more digits if
they don't exist in the C<image> table as a record with a current
article number.

If you need image names of this form, put them elsewhere, or
reconfigure the managed images directory.

=head1 DESCRIPTION

Scans the C<image> table looking for images that don't have an
article, and for image files that don't have image records.

The first is required due to a bug in older versions that left the
image records around when deleting an article.  It's also a recovery
tool just in case the database loses referential integrity, since
MySQL doesn't enforce it.

The second is required for two reasons:

=over

=item

older versions didn't remove the image files when images were removed

=item

you may have deleted articles with images under an older version,
which would have left the image records (and the image files)

=back

=head1 AUTHOR

Tony Cook <tony@develop-help.com>

=cut
