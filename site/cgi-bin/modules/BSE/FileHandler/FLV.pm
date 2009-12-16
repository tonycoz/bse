package BSE::FileHandler::FLV;
use strict;
use base "BSE::FileHandler::Base";
use BSE::Util::Tags qw(tag_hash);
use DevHelp::HTML;

sub process_file {
  my ($self, $file) = @_;

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

  my @missing;
  for my $name (qw/video_width video_height duration/) {
    $info{$name} or push @missing, $name;
  }
  @missing
    and die "Missing required metadata @missing\n";

  $file->add_meta(name => 'width', value => $info{video_width});
  $file->add_meta(name => 'height', value => $info{video_height});
  my $dur_secs = sprintf("%.0f", $info{duration}/1000);
  $file->add_meta(name => 'duration', value => $dur_secs);
  my $fmt_dur = sprintf("%02d:%02d:%02d", $dur_secs / 3600, ($dur_secs / 60) % 60,
			$dur_secs % 60);
  $file->add_meta(name => "duration_formatted", value => $fmt_dur);
  $file->add_meta(name => 'audio_type', value => $info{audio_type});

  if ($self->cfg_entry("ffmpeg", 1)) {
    my $raw_frame = $self->cfg_entry("raw_frame", 1);
    my $fmt = $self->cfg_entry("frame_fmt", "jpeg");
    my $content_type = $self->cfg_entry("frame_content_type", "image/$fmt");
    my $bin = $self->cfg_entry("ffmpeg_bin", "ffmpeg");
    my $debug = $self->cfg_entry("debug", 0);
    my @geo_names = split /,/, $self->cfg_entry("frame_thumbs");
    my @cvt_options = split /,/, $self->cfg_entry("ffmpeg_options");
    my $ss = 2+ rand(10);
    my $cmd = "$bin -i " . $file->full_filename($self->cfg) . " -vcodec ppm -ss $ss -vframes 1 @cvt_options -f image2 -";
    my $redir = $debug ? "" : "2>/dev/null";
    my $ppm_data = `$cmd $redir`;

    $?
      and die "Cannot extract placeholder image\n";

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
		      content_type => $content_type);
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
	   $info{video_width},
	   $info{video_height},
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
			value => $twidth);
	$file->add_meta(name => "ph_${geo_name}_height",
			value => $theight);
	$file->add_meta(name => "ph_${geo_name}_data",
			value => $thumb_data,
			content_type => $content_type);
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
  if ($parms =~ s/\btemplate=(\w+)//
     || $parms =~ /^(\w+)$/) {
    $template .= "_$1";
  }

  my %acts =
    (
     BSE::Util::Tags->static(undef, $self->cfg),
     meta => [ \&tag_hash, \%meta ],
     file => [ \&tag_hash, $file ],
     src => scalar(escape_html($file->url)),
    );

  return BSE::Template->get_page($template, $self->cfg, \%acts, );
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

=back

=cut
