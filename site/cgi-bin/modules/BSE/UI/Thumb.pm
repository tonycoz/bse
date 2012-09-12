package BSE::UI::Thumb;
use strict;
use base 'BSE::UI::Dispatch'; # for error
use BSE::CfgInfo qw(cfg_scalecache_dir cfg_scalecache_uri);
use BSE::Util::Thumb;

our $VERSION = "1.005";

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
  my $source = $cgi->param("s") || "article";
  my $cache = $cgi->param("cache");
  defined $cache or $cache = 1;
  my $error;
  my $geometry = $cfg->entry('thumb geometries', $geometry_id)
    or return $class->error($req, "** cannot find thumb geometry $geometry_id **");
  $thumbs->validate_geometry($geometry, \$error)
    or return $class->error($req, "invalid geometry string: $error");
  
  my $image;
  if ($source eq "article") {
    require BSE::TB::Images;
    $image = BSE::TB::Images->getByPkey($image_id);
    $image && $image->{articleId} == $article_id
      or return $class->error($req, "image not found");
  }
  elsif ($source eq "file") {
    require BSE::TB::Files;
    $image = BSE::TB::Files->getByPkey($image_id)
      or return $class->error($req, "image not found");
  }

  my $do_cache = $cfg->entry('basic', 'cache_thumbnails', 1) && $cache;
  
  my $cache_dir = cfg_scalecache_dir($cfg);
  my $cache_base_url = cfg_scalecache_uri($cfg);

  my ($start_type) = $image->filename =~ /\.(\w+)$/;
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

    my $filename = $image->full_filename;
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
