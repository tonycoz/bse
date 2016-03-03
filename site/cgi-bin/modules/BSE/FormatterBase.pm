package BSE::FormatterBase;
use strict;

our $VERSION = "1.001";

=head1 NAME

BSE::FormatterBase - mixin for adding a format() method.

=head1 SYNOPSIS

  # some article class does
  use parent "BSE::FormatterClass";

  # some article user does
  my $html = $self->format
    (
     text => ..., # default to $self->body
     images => ..., # default to $self->images
     files => ..., # default to $self->files
     gen => ..., # required for embedding
     abs_urls => ..., # defaults to FALSE
    );

=cut


sub formatter_class {
  my ($self) = @_;

  require BSE::Formatter::Article;
  return "BSE::Formatter::Article";
}

=head1 METHODS

=over

=item format()

Format in a body text sort of way.

Parameters:

=over

=item *

C<text> - the body text to format, defaults to the article's body text

=item *

C<images> - the images to use for the image[] tags, defaults to the
article's images.

=item *

C<files> - the files to use for the file[] tags, defaults to the
article's files.

=item *

C<gen> - must be set to the parent generator object for embedding to
work.

=item *

C<articles> - the articles collection class.  Internal use only.

=item *

C<abs_urls> - whether to use absolute URLs.  Default: FALSE.

=item *

C<cfg> - the config object.  Defaults to the global config object.

=back

Template use:

  <:# generator only available in static replacement :>
  <:= article.format("gen", generator) :>

=cut

sub format {
  my ($self, %opts) = @_;

  my $cfg = $opts{cfg} || BSE::Cfg->single;

  my $text = $opts{text};
  defined $text or $text = $self->body;
  my $images = $opts{images};
  defined $images or $images = [ $self->images ];
  my $files = $opts{files};
  defined $files or $files = [ $self->files ];
  my $gen = $opts{gen};
  my $articles = $opts{articles} || "BSE::TB::Articles";
  my $abs_urls = $opts{abs_urls};
  defined $abs_urls or $abs_urls = 0;

  my $formatter_class = $self->formatter_class;

  my $auto_images;
  my $formatter = $formatter_class->new(gen => $gen, 
					articles => $articles,
					abs_urls => $abs_urls, 
					auto_images => \$auto_images,
					images => $images, 
					files => $files);

  return $formatter->format($text);
}

=item unformat()

Remove body text type formatting.

Parameters:

=over

=item *

C<text> - the body text to format, defaults to the article's body text

=item *

C<images> - the images to use for the image[] tags, defaults to the
article's images.

=item *

C<files> - the files to use for the file[] tags, defaults to the
article's files.

=item *

C<gen> - must be set to the parent generator object for embedding to
work.

=item *

C<articles> - the articles collection class.  Internal use only.

=item *

C<abs_urls> - whether to use absolute URLs.  Default: FALSE.

=item *

C<cfg> - the config object.  Defaults to the global config object.

=back

=cut

sub unformat {
  my ($self, %opts) = @_;

  my $cfg = $opts{cfg} || BSE::Cfg->single;

  my $text = $opts{text};
  defined $text or $text = $self->body;
  my $images = $opts{images};
  defined $images or $images = [ $self->images ];
  my $files = $opts{files};
  defined $files or $files = [ $self->files ];
  my $gen = $opts{gen};
  my $articles = $opts{articles} || "BSE::TB::Articles";
  my $abs_urls = $opts{abs_urls};
  defined $abs_urls or $abs_urls = 0;

  my $formatter_class = $self->formatter_class;

  my $auto_images;
  my $formatter = $formatter_class->new(gen => $gen, 
					articles => $articles,
					abs_urls => $abs_urls, 
					auto_images => \$auto_images,
					images => $images, 
					files => $files);

  return $formatter->remove_format($text);
}

1;

=back

=head1 AUTHOR

Tony Cook <tony@develop-help.com>

=cut
