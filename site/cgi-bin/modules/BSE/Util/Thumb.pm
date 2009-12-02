package BSE::Util::Thumb;
use strict;
use BSE::TB::Images;
use BSE::CfgInfo qw(cfg_image_dir);
use BSE::StorageMgr::Thumbs;

# returns a list of $url, $filename, $basename
sub generate_thumb {
  my ($class, $cfg, $image, $geometry_id, $thumbs) = @_;

  my $geometry = $cfg->entry('thumb geometries', $geometry_id);
  unless ($geometry) {
    warn "Cannot find thumb geometry $geometry_id";
    die "Unknown geometry $geometry_id\n";
  }

  my $image_dir = cfg_image_dir($cfg);
  my $cache_dir = $cfg->entry('paths', 'scalecache', "$image_dir/scaled");
  my $cache_base_url = $cfg->entry('paths', 'scalecacheurl', '/images/scaled');

  my ($start_type) = $image->{image} =~ /\.(\w+)$/;
  $start_type ||= 'png';

  my ($width, $height, $type) = 
    $thumbs->thumb_dimensions_sized($geometry, @$image{qw/width height/}, $start_type);
  
  my $basename = "$geometry_id-$image->{image}";

  if ($type eq 'jpeg' && $basename !~ /\.jpe?g$/i) {
    $basename .= ".jpg";
  }
  elsif ($basename !~ /\.$type$/i) {
    $basename .= ".$type";
  }

  my $cache_name = "$cache_dir/$basename";
  my $cache_url = "$cache_base_url/$basename";

  my $storage = BSE::StorageMgr::Thumbs->new(cfg => $cfg);

  if (-e $cache_name) {
    $cache_url = $storage->url($basename);
  }
  else {
    my $image_filename = "$image_dir/$image->{image}";
    unless (-e $image_filename) {
      warn "Image file $image_filename missing\n";
      die "Image file $image->{image} missing\n";
    }

    my $error;
    (my $data, $type) =
      $thumbs->thumb_data($image_filename, $geometry, \$error)
	or return;

    if (open IMAGE, ">$cache_name") {
      binmode IMAGE;
      print IMAGE $data;
      close IMAGE;

      $cache_url = $storage->store($basename);
    }
    else {
      warn "Could not create scaled image cache file $cache_name: $!\n";
      return ( undef, undef, undef, $data, $type );
    }
  }

  return ( $cache_url, $cache_name, $basename );
}

1;
