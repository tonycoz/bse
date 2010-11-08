package AdminUtil;
use strict;

our $VERSION = "1.000";

require Exporter;
use base qw(Exporter);
use vars qw/@EXPORT_OK/;
@EXPORT_OK = qw(save_thumbnail);

sub save_thumbnail {
  my ($original, $newdata) = @_;

  use CGI qw(param);

  unless ($original) {
    @$newdata{qw/thumbImage thumbWidth thumbHeight/} = ('', 0, 0);
  }
  use Constants '$IMAGEDIR';
  if (param('remove_thumb') && $original && $original->{thumbImage}) {
    unlink("$IMAGEDIR/$original->{thumbImage}");
    @$newdata{qw/thumbImage thumbWidth thumbHeight/} = ('', 0, 0);
  }
  my $image = param('thumbnail');
  if ($image && -s $image) {
    # where to put it...
    my $name = '';
    $image =~ /([\w.-]+)$/ and $name = $1;
    my $filename = time . "_" . $name;

    use Fcntl;
    my $counter = "";
    $filename = time . '_' . $counter . '_' . $name
      until sysopen( OUTPUT, "$IMAGEDIR/$filename", 
                     O_WRONLY| O_CREAT| O_EXCL)
        || ++$counter > 100;

    fileno(OUTPUT) or die "Could not open image file: $!";
    binmode OUTPUT;
    my $buffer;

    #no strict 'refs';

    # read the image in from the browser and output it to our 
    # output filehandle
    print STDERR "\$image ",ref $image,"\n";
    seek $image, 0, 0;
    print OUTPUT $buffer while sysread $image, $buffer, 1024;

    close OUTPUT
      or die "Could not close image output file: $!";

    use Image::Size;

    if ($original && $original->{thumbImage}) {
      #unlink("$IMAGEDIR/$original->{thumbImage}");
    }
    @$newdata{qw/thumbWidth thumbHeight/} = imgsize("$IMAGEDIR/$filename");
    $newdata->{thumbImage} = $filename;
  }
}

1;
