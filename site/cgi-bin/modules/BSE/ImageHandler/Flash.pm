package BSE::ImageHandler::Flash;
use strict;
use base 'BSE::ImageHandler::Base';
use BSE::Util::HTML;
use Carp qw(confess);

our $VERSION = "1.000";

my @flash_opts = qw/quality wmode id play loop menu bgcolor flashvars class/;
my %flash_defs =
  (
   quality => "high",
   wmode => "opaque",
  );

# render tags needed to display the flash
sub _render_low {
  my ($self, $im, $image_url, $opts) = @_;

  my $html = qq(<object classid="clsid:D27CDB6E-AE6D-11cf-96B8-444553540000" codebase="http://download.macromedia.com/pub/shockwave/cabs/flash/swflash.cab#version=6,0,40,0" type="application/x-shockwave-flash" width="$im->{width}" height="$im->{height}");
  my $class = delete $opts->{class};
  defined $class and $html .= qq( class="$class");
  my $id = delete $opts->{id};
  defined $id and $html .= qq( id="$id");
  $html .=">";
  $html .= qq(<param name="movie" value="$image_url" />);
  for my $opt (keys %$opts) {
    $html .= qq(<param name="$opt" value=") 
      . escape_html($opts->{$opt}) . qq(" />);
  }
  $html .= qq(<embed src="$image_url");
  for my $opt (keys %$opts) {
    $html .= qq( $opt=") . escape_html($opts->{$opt}) . '"';
  }
  defined $id and $html .= qq( name="$id");
  $html .= qq( height="$im->{height}" width="$im->{width}");
  $html .= q( type="application/x-shockwave-flash" pluginspage="http://www.macromedia.com/go/getflashplayer"></embed></object>);

  return $html;
}

sub format {
  my ($self, %opts) = @_;

  my $im = delete $opts{image};
  my $cfg = $self->cfg;
  my $align = $opts{align} || '';
  my $rest = delete $opts{extras};
  defined $rest or $rest = '';

  my $image_url = $im->image_url($cfg);

  my $type = _flash_var($rest, "type");
  my $section = defined $type ? "embedded $type flash" : "embedded flash";

  my %flash_opts = %flash_defs;
  for my $opt (@flash_opts) {
    my $value = _flash_var($rest, $opt);
    defined $value or $value = $cfg->entry($section, $opt);
    defined $value and $flash_opts{$opt} = $value;
  }

  return $self->_render_low($im, $image_url, \%flash_opts);
}

sub _flash_var {
  my ($str, $name) = @_;

  if ($str =~ /\bflash:\Q$name\E=(["'])((?:\\"|\\'|\\\\|[^"'\\])*)\1/) {
    return $1;
  }
  elsif ($str =~ /\bflash:\Q$name\E=(\S*)/) {
    return $1;
  }
  return;
}

sub _make_thumb_hash {
  my ($self, $geo_id, $im, $static) = @_;

  my $cfg = $self->cfg;
  my $debug = $cfg->entry('debug', 'thumbnails', 0);

  $static ||= 0;

  $debug
    and print STDERR "_make_thumb_hash(..., $geo_id, $im->{src}, ..., $static)\n";

  $geo_id =~ /^[\w,]+$/
    or return ( undef, "* invalid geometry id *" );

  my $geometry = $cfg->entry('thumb geometries', $geo_id)
    or return ( undef, "* cannot find thumb geometry $geo_id *" );

  my $thumbs_class = $cfg->entry('editor', 'thumbs_class')
    or return ( undef, '* no thumbnail engine configured *' );

  (my $thumbs_file = $thumbs_class . ".pm") =~ s!::!/!g;
  require $thumbs_file;
  my $thumbs = $thumbs_class->new($cfg);

  $debug
    and print STDERR "  Thumb class $thumbs_class\n";

  my $error;
  $thumbs->validate_geometry($geometry, \$error)
    or return ( undef, "* invalid geometry string: $error *" );

  my %im = map { $_ => $im->{$_} } $im->columns;

  @im{qw/width height type original/} = 
    $thumbs->thumb_dimensions_sized($geometry, @$im{qw/width height/});

  # leave the source as the original SWF

  return \%im;
}

sub thumb {
  my ($self, %opts) = @_;

  my $geo_id = delete $opts{geo};
  defined $geo_id
    or confess "Missing geo parameter";
  my $im = delete $opts{image}
    or confess "Missing image parameter";
  my $field = delete $opts{field} || '';
  my $static = delete $opts{static} || 0;

  my ($imwork, $error) = 
    $self->_make_thumb_hash($geo_id, $im, $static);

  $imwork
    or return escape_html($error);

  if ($field) {
    my $value = $imwork->{$field};
    defined $value or $value = '';
    return escape_html($value);
  }
  else {
    my $cfg = $self->cfg;
    my %flash_opts = %flash_defs;
    for my $opt (@flash_opts) {
      my $value = $cfg->entry("flash thumbnail $geo_id", $opt);
      defined $value or $value =  $cfg->entry("flash thumbnail", $opt);
      defined $value and $flash_opts{$opt} = $value;
    }

    return $self->_render_low($imwork, $im->image_url($cfg), \%flash_opts);
  }
}

sub inline {
  my ($self, %opts) = @_;

  my $image = delete $opts{image}
    or confess "Missing image parameter";
  my $align = delete $opts{align}
    or confess "Missing align parameter";

  my %flash_opts = 
    (
     %flash_defs,
     class => "bse_flash_$align",
    );
  my $cfg = $self->cfg;
  for my $opt (@flash_opts) {
    my $value = $cfg->entry("flash inline", $opt);
    defined $value and $flash_opts{$opt} = $value;
  }

  my $image_url = $image->image_url($self->{cfg});
  return $self->_render_low
    (
     $image,
     $image_url,
     \%flash_opts,
    );
}

sub popimage {
  return "* popimage can't be used for Flash *";
}

1;

=head1 NAME

BSE::ImageHandler::Flash - handle "image" display for flash

=head1 DESCRIPTION

This module provides display rendering and limited thumbnail rendering
for flash content in the image manager.

For image[] and <:image ...:> tags, any value flash:I<name>=I<value>
where I<name> is in the following will be used to set the
corresponding value for the generated object/embed tags:

=over

=item *

quality - Default "high",

=item *

wmode - default "opaque".

=item *

id - sets id for object, name for embed.  Default: not set.

=item *

play, loop, menu, bgcolor, flashvars.  Default: not set.

=cut
