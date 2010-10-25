package BSE::FileHandler::FLV;
use strict;
use base "BSE::FileHandler::Base";
use BSE::Util::Tags qw(tag_hash);
use BSE::Util::HTML;

sub process_file {
  my ($self, $file) = @_;

  my $debug = $self->cfg_entry("debug", 0);

  my %info;
  unless 
    (eval {
      local $SIG{__DIE__};
      require FLV::Info;
      my $reader = FLV::Info->new;
      $reader->parse($file->full_filename($self->cfg));
      %info = $reader->get_info;
      1;
    }) {
    die "Cannot parse as FLV: $@\n";
  }

  if ($debug) {
    print STDERR "FLV info:\n";
    print STDERR "  $_=$info{$_}\n" for keys %info;
  }

  my $height = $info{video_height} || $info{meta_height};
  my $width = $info{video_width} || $info{meta_width};
  my $duration = $info{duration};

  my @missing;
  $height or push @missing, "video_height/meta_height";
  $width or push @missing, "video_width/meta_width";
  $duration or push @missing, "duration";
  @missing
    and die "Missing required metadata @missing\n";

  $file->add_meta(name => 'width', value => $width,
		  appdata => 0);
  $file->add_meta(name => 'height', value => $height,
		  appdata => 0);
  my $dur_secs = sprintf("%.0f", $duration/1000);
  $file->add_meta(name => 'duration', value => $dur_secs,
		  appdata => 0);
  my $fmt_dur = sprintf("%02d:%02d:%02d", $dur_secs / 3600, ($dur_secs / 60) % 60,
			$dur_secs % 60);
  $file->add_meta(name => "duration_formatted", value => $fmt_dur,
		  appdata => 0);
  $file->add_meta(name => 'audio_type', value => $info{audio_type},
		  appdata => 0);

  if ($self->_have_ffmpeg) {
    my $raw_frame = $self->_save_raw_frame;
    my $fmt = $self->cfg_entry("frame_fmt", "jpeg");
    my $content_type = $self->cfg_entry("frame_content_type", "image/$fmt");
    my $bin = $self->cfg_entry("ffmpeg_bin", "ffmpeg");
    my @geo_names = $self->_thumb_geometries;
    my @cvt_options = split /,/, $self->cfg_entry("ffmpeg_options", "");
    my $ss = 2+ rand(10);
    if ($ss > $dur_secs / 2) {
      $ss = $dur_secs / 2;
    }
    my $cmd = "$bin -i " . $file->full_filename($self->cfg) . " -vcodec ppm -ss $ss -vframes 1 @cvt_options -f image2 -";
    my $redir = $debug ? "" : "2>/dev/null";
    $debug and print STDERR "Cmd: $cmd\n";
    my $ppm_data = `$cmd $redir`;

    $?
      and die "Cannot extract placeholder image\n";
    length $ppm_data
      or die "No raw image data received from ffmpeg\n";

    if ($raw_frame) {
      my $image_data = '';
      require Imager;
      my $im = Imager->new;
      $im->read(data => $ppm_data, type => "pnm")
	or die "Cannot load placeholder image: ", $im->errstr, "\n";
      
      $im->write(data => \$image_data, type => $fmt, @cvt_options)
      or die "Cannot produce final placeholder data: ", $im->errstr, "\n";
      $file->add_meta(name => "ph_data",
		      value => $image_data,
		      content_type => $content_type,
		      appdata => 0);
      $file->add_meta(name => "ph_width",
		      value => $width,
		      appdata => 0);
      $file->add_meta(name => "ph_height",
		      value => $height,
		      appdata => 0);
    }

    if (@geo_names) {
      my $thumbs = $self->_get_thumbs_class;
      for my $geo_name (@geo_names) {
	my $geometry = $self->cfg->entry('thumb geometries', $geo_name)
	  or die "Cannot find thumb geometry $geo_name\n";
	my $thumb_data = '';
	my $error;
	my ($twidth, $theight, $type, $original) =
	  $thumbs->thumb_dimensions_sized
	  (
	   $geometry,
	   $width,
	   $height,
	   undef
	  );
	($thumb_data, $content_type) = $thumbs->thumb_data
	  (
	   data => $ppm_data,
	   geometry => $geometry,
	   error => \$error
	  )
	    or die "Cannot thumb captured frame; $error\n";
	$file->add_meta(name => "ph_${geo_name}_width",
			value => $twidth,
			appdata => 0);
	$file->add_meta(name => "ph_${geo_name}_height",
			value => $theight,
			appdata => 0);
	$file->add_meta(name => "ph_${geo_name}_data",
			value => $thumb_data,
			content_type => $content_type,
			appdata => 0);
      }
    }

  }

  return 1;
}

sub section {
  return "flv handler";
}

sub _get_thumbs_class {
  my ($self) = @_;

  my $class = $self->cfg->entry('editor', 'thumbs_class')
    or return;
  
  (my $filename = "$class.pm") =~ s!::!/!g;
  eval { require $filename; };
  if ($@) {
    print STDERR "** Error loading thumbs_class $class ($filename): $@\n";
    return;
  }
  my $obj;
  eval { $obj = $class->new($self->{cfg}) };
  if ($@) {
    print STDERR "** Error creating thumbs objects $class: $@\n";
    return;
  }

  return $obj;
}

sub inline {
  my ($self, $file, $parms) = @_;

  defined $parms or $parms = '';

  require BSE::Template;
  my %meta = map { $_->name => $_->value }
    grep $_->content_type eq "text/plain", $file->metadata;

  my $base_template = "inline/flv";
  my $template = $base_template;
  my $type = '';
  if ($parms =~ s/\btemplate=(\w+)//
     || $parms =~ /^(\w+)$/) {
    $type .= $1;
  }
  $type ||= $self->cfg_entry("defaultinline");
  $type and $template .= "_$type";

  my %acts =
    (
     BSE::Util::Tags->static(undef, $self->cfg),
     meta => [ \&tag_hash, \%meta ],
     file => [ \&tag_hash, $file ],
     src => scalar(escape_html($file->url($self->cfg))),
    );

  return BSE::Template->get_page($template, $self->cfg, \%acts);
}

sub metaprefix { "flv" }

sub metametadata {
  my ($self) = @_;

  my @fields =
    (
     {
      name => "width",
      title => "Video Width",
      unit => "pixels",
      type => "integer",
     },
     {
      name => "height",
      title => "Video Height",
      unit => "pixels",
      type => "integer",
     },
     {
      name => "duration",
      title => "Video Duration",
      unit => "seconds",
      type => "real",
     },
     {
      name => "duration_formatted",
      title => "Formatted Video Duration",
      unit => "(hh:mm:ss)",
      type => "string",
     },
     {
      name => "audio_type",
      title => "Audio Format",
      type => "enum",
      values => "mono;stereo",
      labels => "Mono;Stereo",
     },
    );
  if ($self->_have_ffmpeg) {
    if ($self->_save_raw_frame) {
      push @fields,
	{
	 name => "ph",
	 title => "Placeholder",
	 type => "image"
	};
    }

    for my $geo ($self->_thumb_geometries) {
      push @fields,
	{
	 name => "ph_${geo}",
	 title => "\u$geo thumbnail of placeholder",
	 type => "image",
	};
    }
  }

  return @fields;
}

sub _have_ffmpeg {
  my $self = shift;

  return $self->cfg_entry("ffmpeg", 1);
}

sub _save_raw_frame {
  my $self = shift;

  return $self->cfg_entry("raw_frame", 1);
}

sub _thumb_geometries {
  my $self = shift;

  return split /,/, $self->cfg_entry("frame_thumbs", "")
}

1;

=item NAME

BSE::FileHandler::FLV - file metadata generator for FLV files

=item Configuration

  [flv handler]
  ffmpeg=1
  raw_frame=1
  frame_fmt=jpeg
  ; following defaults to image/(frame_fmt)
  frame_content_type=image/jpeg
  ffmpeg_bin=ffmpeg
  frame_thumbs=geoname1,geoname2
  defaultinline=template

=over

=item *

ffmpeg - if non-zero, which is the default, ffmpeg is used to extract
a single frame for use as a placeholder image.

=item *

raw_frame - if non-zero, which is the default, the frame extracted
with ffmpeg is added as metadata with name C<ph_data>.

=item *

frame_fmt - the image format of the C<ph_data> image.  Default: jpeg.

=item *

frame_content_type - the MIME content type of the C<ph_data> image,
defaults to "image/" followed by the value of frame_fmt.

=item *

ffmpeg_bin - the name of the ffmpeg binary.  If ffmpeg is in the PATH
this can be left as just C<ffmpeg>, otherwise set this to the full
path to ffmpeg.

=item *

frame_thumbs - geometry names separated by commas for extra
thumbnailed placeholder images, attached as C<ph_>I<geometry>C<_data>
metadata to the file, with the width and height in
C<ph_>I<geometry>C<_width> and C<ph_>I<geometry>C<_height>.

=item *

defaultinline - the default inline view to use.  Default: inline/flv.
A value of xxx will use inline/flv_xxx, just as if you'd done
file[id|xxx] or <:file - xxx:>

=back

=head1 Processing

=head2 Inline Display

If no type parameter is supplied, eg file[id] or <:file -:> and no
default is set by defaultinline, the inline/flv.tmpl is used to
present the FLV.

Otherwise inline/flv_I<type>.tmpl is used.

=head2 Metacontent

Uses /meta/flv_I<name>.tmpl.

Both the inline display templates and the metacontent templates allow
the following tags:

=over

=item *

Standard static tags (not article tags.)

=item *

meta I<name> - retrieves the named text metadata from the file.

=item *

file I<name> - retrieves the named attribute from the file.

=item *

src - the final URL to the file's content

=back

=head2 Metadata

The following metadata entries are set for the file:

=over

=item *

width, height - the width and height of the video

=item *

duration - duration in seconds rounded to an integer

=item *

duration_formatted - duration formatted as HH:MM:SS

=item *

audio_type - audio type (stereo vs mono)

=item *

ph_data - sample frame from the video.  Not saved if [flv
handler].raw_frame is 0.

=item *

ph_I<geometry>_width, ph_I<geometry>_height, ph_I<geometry>_data - the
width, height and content for thumbnails configured via [flv
handler].frame_thumbs.  ph_I<geometry>_data is binary content and
cannot be inserted in the template.

=back

=head1 Provided inline templates

=head1 inline/flv.tmpl

Displays the video inline using flvplayer.swf.

=head1 inline/flv_small.tmpl

Displays a placeholder image inline, clicking pops up a player using
flvplayer.swf (included)

=head1 inline/flv_flow.tmpl

Displays a placeholder image inline, clicking pops up a player using
flowplayer (not included due to license.)  This also retrieves the
play list from the server so that the content URL is not included in
the page (but is trivially fetchable anyway.)

=cut
