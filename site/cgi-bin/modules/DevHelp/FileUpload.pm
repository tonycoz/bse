package DevHelp::FileUpload;
use strict;
use IO::File;
use File::Copy;

=head1 NAME

  DevHelp::FileUpload - tools to maintain a file upload directory

=head1 SYNOPSIS

  use DevHelp::FileUpload;

  my $msg;
  my ($name, $handle) = 
    DevHelp::FileUpload->make_img_filename($image_dir, $original_name, \$msg)
      or die $msg;
  my $newname = 
    DevHelp::FileUpload->make_img_copy($image_dir, $oldname, \$msg)
      or die $msg;

=head1 DESCRIPTION

=over

=item DevHelp::FileUpload->make_img_copy($imgdir, $oldname, \$msg)

=cut

sub make_img_copy {
  my ($class, $imgdir, $oldname, $rmsg) = @_;

  # remove the time value and optional counter
  (my $workname = $oldname) =~ s/^\d+_(?:\d+_)?//;

  my ($newname, $fh) = $class->make_img_filename($imgdir, $workname, $rmsg)
    or return;

  unless (copy("$imgdir/$oldname", $fh)) {
    $$rmsg = "Cannot copy to new file: $!";
    close $fh; undef $fh;
    unlink "$imgdir/$newname";
    return;
  }
    
  close $fh;
  undef $fh;

  return $newname;
}

=item DevHelp::FileUpload->make_img_filename($imgdir, $name, \$msg)

=cut

sub make_img_filename {
  my ($class, $imgdir, $name, $rmsg) = @_;

  my $basename = '';
  $name =~ /([\w.-]+)$/ and $basename = $1;

  my $filename = time . '_' . $basename;

  my $fh;
  my $counter = "";
  $filename = time . '_' . $counter . '_' . $basename
    until $fh = IO::File->new("$imgdir/$filename", O_CREAT | O_WRONLY | O_EXCL)
      or ++$counter > 100;

  unless ($fh) {
    $$rmsg = "Could not open image file $imgdir/$filename: $!";
    return;
  }

  binmode $fh;

  return ($filename, $fh);
}

=back

=head1 AUTHOR

Tony Cook <tony@develop-help.com>

=cut

1;
