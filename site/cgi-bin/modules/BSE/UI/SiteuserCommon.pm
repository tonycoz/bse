package BSE::UI::SiteuserCommon;
use strict;
use BSE::Util::HTML;
use BSE::Util::Tags qw(tag_hash);

our $VERSION = "1.000";

use constant MAXWIDTH => 10000;
use constant MAXHEIGHT => 10000;
use constant MAXSIZE => 1_000_000;
use constant MINRATIO => 0;
use constant MAXRATIO => 1000;

my %image_types =
  (
   GIF => 'image/gif',
   JPG => 'image/jpeg',
   PNG => 'image/png',
   TIF => 'image/tiff',
   BMP => 'image/bmp',
  );

sub _save_images {
  my ($class, $cfg, $cgi, $user, $errors) = @_;

  my %images = map { $_->{image_id} => $_ } $user->images;
  my @templates = $user->images_cfg($cfg);
  my %replace;
  my %delete;

  my $image_dir = $cfg->entryVar('paths', 'siteuser_images');

  require DevHelp::FileUpload;
  require Image::Size;

  my @new_files;

  for my $defn (@templates) {
    my $id = $defn->{id};

    my $file_param = "image_${id}_file";
    my $filename = $cgi->param($file_param);
    my $alt = $cgi->param("image_${id}_alt");
    my $delete = $cgi->param("image_${id}_delete");

    if ($filename) {
      my $msg;
      my ($work_file, $work_fh) = DevHelp::FileUpload->make_img_filename
	($image_dir, $filename, \$msg);
      unless ($work_fh) {
	$errors->{$file_param} = $msg;
	next;
      }
      my $work_fullname = "$image_dir/$work_file";
      local $/ = \4096;
      my $in_fh = $cgi->upload($file_param);
      my $data;
      while (defined($data = <$in_fh>)) {
	print $work_fh $data;
      }
      close $work_fh;

      push @new_files, $work_fullname;

      # image parameter validation
      my ($width, $height, $type) = Image::Size::imgsize($work_fullname);
      unless (defined $width) {
	$errors->{$file_param} = "Error determining image size: $type";
	unlink $work_fullname;
	next;
      }
      unless ($image_types{$type}) {
	$errors->{$file_param} = "Unsupported image format";
	unlink $work_fullname;
	next;
      }
      my $space = -s $work_fullname;
      
      my $minwidth = $defn->{minwidth} || 1;
      $minwidth = 1 if $minwidth < 1;
      my $minheight = $defn->{minheight} || 1;
      $minheight = 1 if $minheight < 1;
      my $maxwidth = $defn->{maxwidth} || MAXWIDTH;
      my $maxheight = $defn->{maxheight} || MAXHEIGHT;
      my $minratio = $defn->{minratio} || MINRATIO;
      my $maxratio = $defn->{maxratio} || MAXRATIO;
      my $maxspace = $defn->{maxspace} || MAXSIZE;
      my %msg_names = 
	( 
	 name => $defn->{description}, 
	 width => $width, 
	 height => $height,
	 minw => $minwidth,
	 maxw => $maxwidth,
	 minh => $minheight,
	 maxh => $maxheight,
	 minr => $minratio,
	 maxr => $maxratio,
	 size => $space,
	 maxs => $maxspace,
	);
      
      if ($width < $minwidth) {
	$errors->{$file_param} =
	  $defn->{widthsmallerror} || $defn->{smallerror} 
	    || "\${name} image must be at least \${minw} pixels wide";
      }
      elsif ($width > $maxwidth) {
	$errors->{$file_param} =
	  $defn->{widthlargeerror} || $defn->{largeerror} 
	    || "\${name} image can be at most \${maxw} pixels wide";
      }
      elsif ($height < $minheight) {
	$errors->{$file_param} =
	  $defn->{heightsmallerror} || $defn->{smallerror} 
	    || "\${name} image must be at least \${minh} pixels high";
      }
      elsif ($height > $maxheight) {
	$errors->{$file_param} =
	  $defn->{heightlargeerror} || $defn->{largeerror} 
	    || "\${name} image can be at most \${maxh} pixels high";
      }
      elsif ($space > $maxspace) {
	$errors->{$file_param} = 
	  $defn->{spaceerror} ||
	    "\${name} image uses too much disk space";
      }
      else {
	my $ratio = $width / $height;
	if ($ratio < $minratio || $ratio > $maxratio) {
	  $errors->{$file_param} =
	    $defn->{properror}
	      || "\${name} image is out of proportion";
	}
      }
      if ($errors->{$file_param}) {
	$errors->{$file_param} =~
	  s/\$\{(\w+)\}/exists $msg_names{$1} ? $msg_names{$1} : "\${$1}"/eg;
	next;
      }
      my %image =
	(
	 image_id => $id,
	 filename => $work_file,
	 width => $width,
	 height => $height,
	 bytes => $space,
	 content_type => $image_types{$type},
	 alt => defined($alt) ? $alt : '',
	);
      $replace{$id} = \%image;
    }
    elsif ($delete) {
      ++$delete{$id} if exists $images{$id};
    }
  }

  if (keys %$errors) {
    unlink @new_files;
    return;
  }
  
  for my $id ( map $_->{id}, @templates ) {
    if ($replace{$id}) {
      $user->set_image($cfg, $id => $replace{$id});
    }
    elsif ($delete{$id}) {
      $user->remove_image($cfg, $id);
    }
  }
}

sub iter_images {
  my ($siteuser, $cfg) = @_;

  return $siteuser->images_cfg($cfg);
}

sub tag_siteuser_image {
  my ($siteuser, $cfg, $images, $imgcfg, $rloaded, $args, 
      $acts, $name, $templater) = @_;

  my ($image_id, $what) = DevHelp::Tags->get_parms($args, $acts, $templater)
    or return '';

  unless (keys %$imgcfg) {
    %$imgcfg = map { $_->{id} => $_ } $siteuser->images_cfg($cfg);
    %$images = map { $_->{image_id} => $_ } $siteuser->images if keys %$imgcfg;
  }

  if (!$what) {
    # just checking if the image exists
    return exists $images->{$image_id};
  }
  else {
    my $image_cfg = $imgcfg->{$image_id}
      or return '';

    if (exists $image_cfg->{$what}) {
      return escape_html($image_cfg->{$what});
    }

    my $image = $images->{$image_id}
      or return '';

    if ($what eq 'url') {
      return escape_html
	("/cgi-bin/user.pl?a_image=1&u=$siteuser->{id}&i=$image_id");
    }
    if (exists $image->{$what}) {
      return escape_html($image->{$what});
    }

    return '';
  }
}

sub _edit_tags {
  my ($class, $siteuser, $cfg) = @_;

  my $images_loaded = 0;
  my %images;
  my %imgcfg;
  my $it = BSE::Util::Iterate->new;
  return
    (
     $it->make_iterator([ \&iter_images, $siteuser, $cfg ],
			'imagetemplate', 'imagetemplates' ),
     siteuser_image => 
     [ \&tag_siteuser_image, $siteuser, $cfg, \%images, \%imgcfg, 
       \$images_loaded ],
    );
}

sub _display_tags {
  my ($class, $siteuser, $cfg) = @_;

  my $images_loaded = 0;
  my %images;
  my %imgcfg;
  my $it = BSE::Util::Iterate->new;
  return
    (
     siteuser => [ \&tag_hash, $siteuser ],
     siteuser_image => 
     [ \&tag_siteuser_image, $siteuser, $cfg, \%images, \%imgcfg, 
       \$images_loaded ],
    );
}

1;
