package BSE::Formatter;
use strict;
use BSE::Util::HTML;
use Carp 'confess';

our $VERSION = "1.013";

use base 'DevHelp::Formatter';

my $pop_nameid = 'AAAAAA';

sub new {
  my $class = shift;

  my (%opts) = 
    ( 
     images => [], 
     files => [],
     abs_urls => 0, 
     acts => {}, 
     @_
    );

  my $self = $class->SUPER::new;

  $self->{gen} = $opts{gen};
  $self->{acts} = $opts{acts};
  $self->{articles} = $opts{articles} || "BSE::TB::Articles";
  $self->{abs_urls} = $opts{abs_urls};
  my $dummy;
  $self->{auto_images} = $opts{auto_images} || \$dummy;
  $self->{images} = $opts{images};
  $self->{files} = $opts{files};
  $self->{templater} = $opts{templater};

  my $cfg = $self->{cfg} = $self->{gen} ? $self->{gen}->{cfg} : BSE::Cfg->single;
  if ($cfg->entry('html', 'mbcs', 0)) {
    $self->{conservative_escape} = 1;
  }
  elsif ($cfg->entry('html', 'msentify', 0)) {
    $self->{msentify} = 1;
  }
  $self->{xhtml} = $cfg->entry('basic', 'xhtml', 1);

  $self->{redirect_links} = $cfg->entry('html', 'redirect_links', '');
  $self->{redirect_salt} = $cfg->entry('html', 'redirect_salt', '');

  $self;
}

sub abs_image_urls {
  1;
}

sub _image {
  my ($self, $im, $align, $url, $style) = @_;

  my $extras = '';
  my @classes;
  if ($self->{xhtml}) {
    push @classes, $self->{cfg}->entry
      ("html", "formatter_image_class", "bse_image_inline");
  }
  if ($style) {
    if ($style =~ /^\d/) {
      $extras .= qq! style="padding: $style"!;
    }
    elsif ($style =~ /^\w[\w-]*$/) {
      push @classes, $style;
    }
    else {
      $extras .= qq! style="$style"!;
    }
  }
  if (@classes) {
    $extras .= qq! class="@classes"!;
  }

  return $im->formatted
    (
     cfg => $self->{cfg},
     class => "bse_image_inline",
     align => $align,
     extras => $extras,
     abs_urls => $self->abs_image_urls,
     $url ? ( url => unescape_html($url) ) : (),
    );
}

sub gimage {
  my ($self, $args) = @_;

  my ($name, $align, $url, $style) = split /\|/, $args, 4;
  my $im = $self->{gen}->get_gimage($name);
  if ($im) {
    $self->_image($im, $align, $url, $style);
  }
  else {
    return '';
  }
}

sub image {
  my ($self, $args) = @_;

  my $images = $self->{images};
  my ($index, $align, $url, $style) = split /\|/, $args, 4;
  my $text = '';
  my $im;
  if ($index =~ /^\d+$/) {
    if ($index >=1 && $index <= @$images) {
      $im = $images->[$index-1];
      ${$self->{auto_images}} = 0;
    }
  }
  elsif ($index =~ /^[a-z]\w*$/i){
    # scan the names
    for my $image (@$images) {
      if ($image->{name} && lc $image->{name} eq lc $index) {
	$im = $image;
	last;
      }
    }
  }
  if ($im) {
    return $self->_image($im, $align, $url, $style);
  }
  else {
    return '';
  }
}

sub embed {
  my ($self, $name, $templateid, $maxdepth) = @_;

  $self->{gen} or return "** cannot embed here - missing gen **";

  my $embed;
  if ($name =~ /^[1-9][0-9]*$/) {
    $embed = $self->{articles}->getByPkey($name);
  }
  elsif ($name =~ /\A[a-zA-Z0-9_]*[a-zA-Z][a-zA-Z0-9_]*\z/) {
    $embed = $self->{articles}->getBy(linkAlias => $name);
  }

  $embed or return "** article $name not found **";

  $self->{gen}->_embed_low($embed, $self->{articles}, $templateid, $maxdepth);
}

sub _get_article {
  my ($self, $id, $error) = @_;

  my $cfg = $self->{cfg}
    or confess "cfg not set in acts";
  my $dispid;
  my $art;
  if ($id =~ /^\d+$/) {
    $dispid = $id;
    $art = $self->{articles}->getByPkey($id);
  }
  elsif (my $work = $cfg->entry('articles', $id)) {
    # try to find it in the config
    $dispid = "$id ($work)";
    $id = $work;
    $art = $self->{articles}->getByPkey($id);
  }
  else {
    ($art) = $self->{articles}->getBy(linkAlias => $id);
    unless ($art) {
      $$error = "&#42;&#42; No article name '".escape_html($id)."' found &#42;&#42;";
      return;
    }
  }

  unless ($art) {
    $$error = "&#42;&#42; Cannot find article id $dispid &#42;&#42;";
    return;
  }

  unless ($art->is_linked) {
    $$error = "&#42;&#42; article $dispid doesn't permit links &#42;&#42;";
    return;
  }

  unless ($art->listed) {
    $$error = "&#42;&#42; article $dispid is not listed &#42;&#42;";
    return;
  }

  unless ($art->is_released && !$art->is_expired) {
    $$error = "&#42;&#42; article $dispid is not released or is expired &#42;&#42;";
    return;
  }

  return $art;
}

sub doclink {
  my ($self, $id, $title, $target, $type) = @_;

  my $error;
  my $art = $self->_get_article($id, \$error)
    or return $error;

  my $cfg = $self->{cfg}
    or confess "cfg not set in acts";

  # make the URL absolute if necessary
  my $admin = $self->{gen}{admin_links};
  my $url;
  if ($admin) {
    $url = $art->admin;
    if (!$self->{gen}{admin}) {
      $url .= $url =~ /\?/ ? "&" : "?";
      $url .= "admin=0&admin_links=1";
    }
  }
  else {
    $url = $art->link($self->{cfg});
  }

  unless ($title) {
    $title = escape_html($art->{title});
  }

  if ($url) {
    if ($self->{abs_urls}) {
      $url = $cfg->entryErr('site', 'url') . $url
	unless $url =~ /^\w+:/;
    }
    $url = escape_html($url);
  }


  $url
    or return $title;

  $target = $target ? qq! target="$target"! : '';
  my $title_attrib = escape_html($art->{title});
  my $class_text = '';
  if ($type) {
    my $class = $self->tag_class($type);
    if ($class) {
      $class_text = qq/ class="$class"/; 
    }
  }
  
  return qq!<a href="$url" title="$title_attrib"$target$class_text>$title</a>!;
}

sub popimage {
  my ($self, $args) = @_;

  my ($image_id, $class) = split /\|/, $args;

  return $self->{gen}->do_popimage($image_id, $class, $self->{images});
}

sub gpopimage {
  my ($self, $args) = @_;

  my ($image_id, $class) = split /\|/, $args;

  return $self->{gen}->do_gpopimage($image_id, $class, $self->{images});
}

sub _file {
  my ($self, $file, $text, $type) = @_;

  my $title = defined $text ? $text : escape_html($file->{displayName});
  if ($file->{forSale}) {
    return escape_html($title);
  }
  else {
    my $title_attrib = "Filename: " . escape_html($file->{displayName});
    my $class_text = '';
    if ($type) {
      my $class = $self->tag_class($type);
      if ($class) {
        $class_text = qq/ class="$class"/; 
      }
    }
    my $url = "/cgi-bin/user.pl?download_file=1&file=$file->{id}";
    return qq!<a href="! . escape_html($url) . qq!" title="$title_attrib"$class_text>! .
      $title . "</a>";
  }
}

sub filelink {
  my ($self, $fileid, $text, $type) = @_;

  my ($file) = grep $_->{name} eq $fileid, @{$self->{files}}
    or return "** unknown file $fileid **";

  return $self->_file($file, $text, $type);
}

sub gfilelink {
  my ($self, $fileid, $text, $type) = @_;

  unless ($self->{gfiles}) {
    $self->{gfiles} = [ BSE::TB::Articles->global_files ];
  }
  my ($file) = grep $_->{name} eq $fileid, @{$self->{gfiles}}
    or return "** unknown file $fileid **";

  return $self->_file($file, $text, $type);
}

sub file {
  my ($self, $fileid, $field, $type) = @_;

  my ($file) = grep $_->{name} eq $fileid, @{$self->{files}}
    or return "* unknown file $fileid *";

  return $file->inline
    (
     field => $field,
     cfg => $self->{gen}->cfg,
    );
}

sub thumbimage {
  my ($self, $geo_id, $image_id) = @_;

  return $self->{gen}->do_thumbimage($geo_id, $image_id, '', $self->{images});
}

sub gthumbimage {
  my ($self, $geo_id, $image_id) = @_;

  return $self->{gen}->do_gthumbimage($geo_id, $image_id, '');
}

sub replace {
  my ($self, $rpart) = @_;

  $$rpart =~ s#gthumbimage\[([^\]\[|]+)\|([^\]\[|]+)\]# $self->gthumbimage($1, $2) #ge
    and return 1;
  $$rpart =~ s#thumbimage\[([^\]\[|]+)\|([^\]\[|]+)\]# $self->thumbimage($1, $2) #ge
    and return 1;
  $$rpart =~ s#gimage\[([^\]\[]+)\]# $self->gimage($1) #ige
    and return 1;
  $$rpart =~ s#popdoclink\[([\w-]+)\|([^\]\[]*\n\s*\n[^\]\[]*)\]#
      "\n\n\x02" . $self->doclink($1, $self->_blockify($2), "_blank", 'popdoclink')
	. "\x03\n\n" #ige
    and return 1;
  $$rpart =~ s#popdoclink\[([\w-]+)\|([^\]\[]+)\]# $self->doclink($1, $2, "_blank", 'popdoclink') #ige
    and return 1;
  $$rpart =~ s#popdoclink\[([\w-]+)\]# $self->doclink($1, undef, "_blank", 'popdoclink') #ige
    and return 1;
  $$rpart =~ s#doclink\[([\w-]+)\|([^\]\[]*\n\s*\n[^\]\[]*)\]#
      "\n\n\x02" . $self->doclink($1, $self->_blockify($2), undef, 'doclink')
	. "\x03\n\n" #ige
    and return 1;
  $$rpart =~ s#doclink\[([\w-]+)\|([^\]\[]+)\]# $self->doclink($1, $2, undef, 'doclink') #ige
    and return 1;
  $$rpart =~ s#doclink\[([\w-]+)\]# $self->doclink($1,  undef, undef, 'doclink') #ige
    and return 1;

  $$rpart =~ s#popformlink\[([\w-]+)\|([^\]\[]*\n\s*\n[^\]\[]*)\]#
    "\n\n\x02" . $self->formlink($1, 'popformlink', $self->_blockify($2), '_blank') . "\x03\n\n"#ige
    and return 1;
  $$rpart =~ s#popformlink\[([\w-]+)\|([^\]\[]+)\]#
    $self->formlink($1, 'popformlink', $2, '_blank') #ige
    and return 1;
  $$rpart =~ s#popformlink\[([\w-]+)\]#
    $self->formlink($1, 'popformlink', undef, '_blank') #ige
    and return 1;
  $$rpart =~ s#formlink\[([\w-]+)\|([^\]\[]*\n\s*\n[^\]\[]*)\]#
    "\n\n\x02" . $self->formlink($1, 'formlink', $self->_blockify($2)) . "\x03\n\n" #ige
    and return 1;
  $$rpart =~ s#formlink\[([\w-]+)\|([^\]\[]+)\]#
    $self->formlink($1, 'formlink', $2) #ige
    and return 1;
  $$rpart =~ s#formlink\[([\w-]+)\]# $self->formlink($1, 'formlink', undef) #ige
    and return 1;
  $$rpart =~ s#gfilelink\[(\w+)\|([^\]\[]*\n\s*\n[^\]\[]*)\]#
      "\n\n\x02" . $self->gfilelink($1, $self->_blockify($2), undef, 'gfilelink')
	. "\x03\n\n" #ige
    and return 1;
  $$rpart =~ s#gfilelink\[\s*(\w+)\s*\|([^\]\[]+)\]# $self->gfilelink($1, $2, 'gfilelink') #ige
      and return 1;
  $$rpart =~ s#gfilelink\[\s*(\w+)\s*\]# $self->gfilelink($1, undef, 'gfilelink') #ige
      and return 1;
  $$rpart =~ s#filelink\[(\w+)\|([^\]\[]*\n\s*\n[^\]\[]*)\]#
      "\n\n\x02" . $self->filelink($1, $self->_blockify($2), undef, 'filelink')
	. "\x03\n\n" #ige
    and return 1;
  $$rpart =~ s#filelink\[\s*(\w+)\s*\|([^\]\[]+)\]# $self->filelink($1, $2, 'filelink') #ige
      and return 1;
  $$rpart =~ s#filelink\[\s*(\w+)\s*\]# $self->filelink($1, undef, 'filelink') #ige
      and return 1;
  $$rpart =~ s#file\[(\w+)(?:\|([\w.]*))?\]# $self->file($1, $2, 'file') #ige
    and return 1;
  $$rpart =~ s#gpopimage\[([^\[\]]+)\]# $self->gpopimage($1) #ige
    and return 1;
  $$rpart =~ s#popimage\[([^\[\]]+)\]# $self->popimage($1) #ige
    and return 1;

  return $self->SUPER::replace($rpart);
}

sub formlink {
  my ($self, $id, $type, $text, $target) = @_;

  my $cfg = $self->{cfg};
  my $section = "$id form";
  my $title = escape_html($cfg->entry($section, 'title', "Send us a comment"));
  $text ||= $title;
  my $secure = $cfg->entry($section, 'secure', 0);
  my $abs_url = $self->{abs_urls} || $secure;

  my $prefix = '';
  if ($abs_url) {
    $prefix = $cfg->entryVar('site', $secure ? 'secureurl' : 'url');
  }

  my $extras = '';
  if ($type) {
    my $class = $self->tag_class($type);
    if ($class) {
      $extras .= qq/ class="$class"/;
    }
  }
  if ($target) {
    $extras .= qq/ target="$target"/;
  }

  return qq!<a href="$prefix/cgi-bin/fmail.pl?form=$id" title="$title"$extras>$text</a>!;
}

sub remove_doclink {
  my ($self, $id) = @_;

  my $error;
  my $art = $self->_get_article ($id, \$error)
    or return $error;

  return $art->{title};
}

sub remove_formlink {
  my ($self, $id) = @_;

  return $self->{cfg}->entry("$id form", 'title', "Send us a comment");
}

sub remove_popimage {
  my ($self, $args) = @_;

  my ($image1, $class) = split /\|/, $args;

  my $images = $self->{images};
  if ($image1 =~ /^\d+$/) { # image index
    if ($image1 >= 1 and $image1 <= @$images) {
      return $images->[$image1-1]{alt};
    }
  }
  elsif ($image1 =~ /^\w+$/) { # image name
    my ($image) = grep $_->{name} eq $image1, @$images;
    return $image ? $image->{alt} : '';
  }
  else {
    return $image1;
  }
}

sub remove_gpopimage {
  my ($self, $args) = @_;

  my ($image1, $class) = split /\|/, $args;

  my $im = $self->{gen}->get_gimage($image1);
  if ($im) {
    return $im->{alt};
  }
  else {
    return $image1;
  }
}

sub remove_filelink {
  my ($self, $fileid, $text) = @_;

  my ($file) = grep $_->{name} eq $fileid, @{$self->{files}}
    or return "** unknown file $fileid **";

  return defined $text ? $text : $file->{displayName};
}

sub remove_gfilelink {
  my ($self, $fileid, $text, $type) = @_;

  unless ($self->{gfiles}) {
    $self->{gfiles} = [ BSE::TB::Articles->global_files ];
  }
  my ($file) = grep $_->{name} eq $fileid, @{$self->{gfiles}}
    or return "** unknown file $fileid **";

  return defined $text ? $text : $file->{displayName};
}

sub remove {
  my ($self, $rpart) = @_;

  $$rpart =~ s#g?thumbimage\[([^\]\[|]+)\|([^\]\[|]+)\]##g
    and return 1;
  $$rpart =~ s#gimage\[([^\]\[]+)\]##ig
    and return 1;
  $$rpart =~ s#popdoclink\[([\w-]+)\|([^\]\[]*)\]#$2#ig
    and return 1;
  $$rpart =~ s#popdoclink\[([\w-]+)\]# $self->remove_doclink($1) #ige
    and return 1;
  $$rpart =~ s#doclink\[([\w-]+)\|([^\]\[]*)\]#$2#ig
    and return 1;
  $$rpart =~ s#doclink\[([\w-]+)\]# $self->remove_doclink($1) #ige
    and return 1;

  $$rpart =~ s#popformlink\[([\w-]+)\|([^\]\[]*)\]#$2#ig
    and return 1;
  $$rpart =~ s#popformlink\[([\w-]+)\]# $self->remove_formlink($1) #ige
    and return 1;

  $$rpart =~ s#gfilelink\[\s*(\w+)\s*\|([^\]\[]+)\]# $self->remove_gfilelink($1, $2) #ige
      and return 1;
  $$rpart =~ s#gfilelink\[\s*(\w+)\s*\]# $self->remove_gfilelink($1) #ige
      and return 1;

  $$rpart =~ s#filelink\[\s*(\w+)\s*\|([^\]\[]+)\]# $self->remove_filelink($1, $2) #ige
      and return 1;
  $$rpart =~ s#filelink\[\s*(\w+)\s*\]# $self->remove_filelink($1) #ige
      and return 1;

  $$rpart =~ s#formlink\[([\w-]+)\|([^\]\[]*)\]#$2#ig
    and return 1;
  $$rpart =~ s#formlink\[([\w-]+)\]# $self->remove_formlink($1) #ige
    and return 1;
  $$rpart =~ s#gpopimage\[([^\[\]]+)\]# $self->remove_gpopimage($1) #ige
    and return 1;
  $$rpart =~ s#popimage\[([^\[\]]+)\]# $self->remove_popimage($1) #ige
    and return 1;
  
}

sub tag_class {
  my ($self, $type) = @_;

  my $default = $type eq 'p' ? '' : $type;

  return $self->{cfg}->entry('body class', $type, $default);
}

1;
