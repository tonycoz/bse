package BSE::UI::Thumb;
use strict;
use base 'BSE::UI::Dispatch'; # for error
use Images;
use BSE::CfgInfo qw(cfg_image_dir);

sub dispatch {
  my ($class, $req) = @_;

  my $cfg = $req->cfg;
  my $thumbs_class = $cfg->entry('editor', 'thumbs_class')
    or return '** no thumbnail engine configured **';

  (my $thumbs_file = $thumbs_class . ".pm") =~ s!::!/!g;
  require $thumbs_file;
  my $thumbs = $thumbs_class->new($cfg);

  my $cgi = $req->cgi;
  my $geometry_id = $cgi->param('g');
  my $image_id = $cgi->param('image');
  my $article_id = $cgi->param('page');
  my $error;
  my $geometry = $cfg->entry('thumb geometries', $geometry_id)
    or return $class->error($req, "** cannot find thumb geometry $geometry_id **");
  $thumbs->validate_geometry($geometry, \$error)
    or return $class->error($req, "invalid geometry string: $error");
  
  my $image = Images->getByPkey($image_id);
  $image && $image->{articleId} == $article_id
    or return $class->error($req, "image not found");

  my $do_cache = $cfg->entry('basic', 'cache_thumbnails', 1);
  my $image_dir = cfg_image_dir($cfg);
  
  my $cache_dir = $cfg->entry('paths', 'scalecache', "$image_dir/scaled");
  my $cache_base_url = $cfg->entry('paths', 'scalecacheurl', '/images/scaled');

  my ($start_type) = $image->{image} =~ /\.(\w+)$/;
  $start_type ||= 'png';

  my ($width, $height, $type) = 
    $thumbs->thumb_dimensions_sized($geometry, @$image{qw/width height/}, $start_type);
  
  my $cache_name = "$cache_dir/$geometry_id-$image->{image}";
  my $cache_url = "$cache_base_url/$geometry_id-$image->{image}";

  if ($type eq 'jpeg' && $cache_name !~ /\.jpe?g$/i) {
    $cache_name .= ".jpg";
    $cache_url .= ".jpg";
  }
  elsif ($cache_name !~ /\.$type$/i) {
    $cache_name .= ".$type";
    $cache_url .= ".$type";
  }

  my $image_refresh =
    BSE::Template->get_refresh($cache_url);
  push @{$image_refresh->{headers}}, "Cache-Control: max-age=3600";
  if ($do_cache) {
    -e $cache_name
      and return $image_refresh;
  }
    
  my $filename = "$image_dir/$image->{image}";
  -e $filename 
    or return $class->error($req, "image file missing");
  
  (my $data, $type) = $thumbs->thumb_data($filename, $geometry, \$error)
    or return $class->error($req, $error);

  my $image_result =
    {
     content => $data,
     type => $type,
     headers => [
		 "Content-Length: ".length($data),
		 "Cache-Control: max-age=3600",
		],
    };

  # just return the image if we aren't caching
  $do_cache
    or return $image_result;
  
  if (open IMAGE, "> $cache_name") {
    binmode IMAGE;
    print IMAGE $data;
    close IMAGE;

    # redirect to the image
    return $image_refresh;
  }
  else {
    warn "Could not create scaled image cache file $cache_name: $!\n";
    return $image_result;
  }

}

1;
