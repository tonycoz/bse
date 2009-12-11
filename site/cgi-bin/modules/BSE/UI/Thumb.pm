package BSE::UI::Thumb;
use strict;
use base 'BSE::UI::Dispatch'; # for error
use BSE::TB::Images;
use BSE::CfgInfo qw(cfg_image_dir);
use BSE::Util::Thumb;

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
  
  my $image = BSE::TB::Images->getByPkey($image_id);
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

  if ($do_cache) {
    my ($cache_url, $cache_name, $basename, $data );
    eval {
      ($cache_url, $cache_name, $basename, $data ) = 
	BSE::Util::Thumb->generate_thumb($cfg, $image, $geometry_id, $thumbs);
    };

    $@
      and return $class->error($req, $@);

    if ($cache_url) {
      my $image_refresh =
	BSE::Template->get_refresh($cache_url);
      push @{$image_refresh->{headers}}, "Cache-Control: max-age=3600";
      return $image_refresh;
    }
    elsif ($data) {
      # couldn't save the data for some reason, send it back anyway
      return
	{
	 content => $data,
	 type => $type,
	 headers => [
		     "Content-Length: ".length($data),
		     "Cache-Control: max-age=3600",
		    ],
	};
    }
    else {
      $class->error($req, "Unexpected result trying to get cached image");
    }
  }
  else {
    # not caching, just generate it

    my $filename = "$image_dir/$image->{image}";
    -e $filename 
      or return $class->error($req, "image file missing");
    
    (my $data, $type) = $thumbs->thumb_data
      (
       filename => $filename,
       geometry => $geometry,
       error => \$error
      )
      or return $class->error($req, $error);
    
    return
      {
       content => $data,
       type => $type,
       headers => [
		   "Content-Length: ".length($data),
		   "Cache-Control: max-age=3600",
		  ],
      };
  }
}

1;
