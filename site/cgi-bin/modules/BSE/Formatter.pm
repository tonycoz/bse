package BSE::Formatter;
use strict;
use DevHelp::HTML;
use Carp 'confess';

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
  $self->{articles} = $opts{articles};
  $self->{abs_urls} = $opts{abs_urls};
  my $dummy;
  $self->{auto_images} = $opts{auto_images} || \$dummy;
  $self->{images} = $opts{images};
  $self->{files} = $opts{files};
  $self->{templater} = $opts{templater};

  my $cfg = $self->{gen}->{cfg};
  if ($cfg->entry('html', 'mbcs', 0)) {
    $self->{conservative_escape} = 1;
  }

  $self;
}

sub _image {
  my ($self, $im, $align, $url, $style) = @_;

  my $text = qq!<img src="/images/$im->{image}" width="$im->{width}"!
    . qq! height="$im->{height}" alt="! . escape_html($im->{alt}).'"'
      . qq! border="0"!;
  $text .= qq! align="$align"! if $align && $align ne 'center';
  if ($style) {
    if ($style =~ /^\d/) {
      $text .= qq! style="padding: $style"!;
    }
    elsif ($style =~ /^\w+$/) {
      $text .= qq! class="$style"!;
    }
    else {
      $text .= qq! style="$style"!;
    }
  }
  $text .= qq! />!;
  $text = qq!<div align="center">$text</div>!
    if $align && $align eq 'center';
  # the text in $url would have been HTML escaped already, the url
  # in the image record hasn't been
  if (!$url && $im->{url}) {
    $url = escape_html($im->{url});
  }
  if ($url) {
    $text = qq!<a href="$url">$text</a>!;
  }

  return $text;
}

sub gimage {
  my ($self, $args) = @_;

  my ($name, $align, $url, $style) = split /\|/, $args, 4;
  my $im = $self->{gen}->get_gimage($name);
  if ($im) {
    $self->_image($im, $align, $url);
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

  $self->{gen}->_embed_low($self->{acts}, $self->{articles}, $name,
			   $templateid, $maxdepth, $self->{templater});
}

sub _get_article {
  my ($self, $id, $error) = @_;

  my $cfg = $self->{gen}->{cfg}
    or confess "cfg not set in acts";
  my $dispid;
  if ($id =~ /^\d+$/) {
    $dispid = $id;
  }
  else {
    # try to find it in the config
    my $work = $cfg->entry('articles', $id);
    unless ($work) {
      $$error = "&#42;&#42; No article name '".escape_html($id)."' in the [articles] section of bse.cfg &#42;&#42;";
      return;
    }
    $dispid = "$id ($work)";
    $id = $work;
  }
  my $art = $self->{articles}->getByPkey($id);
  unless ($art) {
    $$error = "&#42;&#42; Cannot find article id $dispid &#42;&#42;";
    return;
  }

  return $art;
}

sub doclink {
  my ($self, $id, $title, $target, $type) = @_;

  my $error;
  my $art = $self->_get_article($id, \$error)
    or return $error;

  my $cfg = $self->{gen}->{cfg}
    or confess "cfg not set in acts";

  # make the URL absolute if necessary
  my $admin = $self->{gen}{admin};
  my $link = $admin ? 'admin' : 'link';
  my $url = $art->{$link};
  if ($self->{abs_urls}) {
    $url = $cfg->entryErr('site', 'url') . $url
      unless $url =~ /^\w+:/;
  }
  $url = escape_html($url);

  unless ($title) {
    $title = escape_html($art->{title});
  }

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

  my $image_id;
  my ($image1_name, $image2_name, $align, $style) = split /\|/, $args;

  my $style_tag = '';
  if ($style =~ /^\d/) {
    $style_tag = qq! style="padding: $style"!;
  }
  elsif ($style =~ /^\w+$/) {
    $style_tag = qq! class="$style"!;
  }
  else {
    $style_tag = qq! style="$style"!;
  }

  # work out the content inside the link
  my $inside;
  my $images = $self->{images};
  if ($image1_name =~ /^\w+$/) {
    my $image1;
    if ($image1_name =~ /^\d+$/) {
      if ($image1_name >= 1 && $image1_name <= @$images) {
	$image1 = $images->[$image1_name - 1];
      }
      else {
	return '';
      }
    }
    else {
      ($image1) = grep $_->{name} && lc $_->{name} eq lc $image1_name,
	@$images;
    }

    $inside = qq!<img src="/images/$image1->{image}" !
      . qq!width="$image1->{width}" height="$image1->{height}"! 
	. qq! alt="! . escape_html($image1->{alt})
	  .qq!" border="0"!;
    $inside .= qq! align="$align"! if $align && $align ne 'center';
    $inside .= $style_tag;
    $image_id = 'popimage_' . $pop_nameid++;

    $inside .= qq! name="$image_id" />!;
  }
  else {
    $inside = $image1_name;
    $image_id = '';
  }

  # resolve the second image
  my $image2;
  if ($image2_name =~ /^\d+$/) {
    if ($image2_name >= 1 and $image2_name < @$images) {
      $image2 = $images->[$image2_name - 1];
    }
    else {
      return '';
    }
  }
  elsif ($image2_name =~ /^\w+$/) {
    ($image2) = grep $_->{name} && lc $_->{name} eq lc $image2_name,
      @$images
	or return '';
  }
  else {
    return "** Unknown image2 $image2_name **";
  }

  my $href = '/cgi-bin/image.pl?id=' . $image2->{articleId} 
    . '&amp;imid=' . $image2->{id};
  my $popup_url = "/images/" . $image2->{image};
  my $javascript = 
    "return bse_popup_image($image2->{articleId}, $image2->{id}, "
      . "$image2->{width}, $image2->{height}, '$image_id', '$popup_url')";
  my $link_start = qq!<a href="$href" onclick="$javascript" target="bse_image">!;
  my $link_end = "</a>";

  if ($image_id) {
    if ($align eq 'center') {
      $link_start = qq!<div align="center">! . $link_start;
      $link_end .= '</div>';
    }
  }
  else {
    if ($align) {
      $link_start = qq!<div align="$align"$style_tag>! . $link_start;
      $link_end .= "</div>";
    }
    elsif ($style_tag) {
      $link_start = "<div$style_tag>".$link_start;
      $link_end .= "</div>";
    }
  }

  return $self->_fix_spanned($link_start, $link_end, $inside);
}

sub filelink {
  my ($self, $fileid, $text) = @_;

  my ($file) = grep $_->{name} eq $fileid, @{$self->{files}}
    or return "** unknown file $fileid **";

  my $title = defined $text ? $text : $file->{displayName};
  if ($file->{forSale}) {
    return escape_html($title);
  }
  else {
    my $url = "/cgi-bin/user.pl?download_file=1&file=$file->{id}";
    return qq!<a href="! . escape_html($url) . qq!">! .
      escape_html($title) . "</a>";
  }
}

sub replace {
  my ($self, $rpart) = @_;

  $$rpart =~ s#gimage\[([^\]\[]+)\]# $self->gimage($1) #ige
    and return 1;
  $$rpart =~ s#popdoclink\[(\w+)\|([^\]\[]+)\]# $self->doclink($1, $2, "_blank", 'popdoclink') #ige
    and return 1;
  $$rpart =~ s#popdoclink\[(\w+)\]# $self->doclink($1, undef, "_blank", 'popdoclink') #ige
    and return 1;
  $$rpart =~ s#doclink\[(\w+)\|([^\]\[]+)\]# $self->doclink($1, $2, undef, 'doclink') #ige
    and return 1;
  $$rpart =~ s#doclink\[(\w+)\]# $self->doclink($1,  undef, undef, 'doclink') #ige
    and return 1;

  $$rpart =~ s#popformlink\[(\w+)\|([^\]\[]+)\]#
    $self->formlink($1, 'popformlink', $2, '_blank') #ige
    and return 1;
  $$rpart =~ s#popformlink\[(\w+)\]#
    $self->formlink($1, 'popformlink', undef, '_blank') #ige
    and return 1;
  $$rpart =~ s#formlink\[(\w+)\|([^\]\[]+)\]#
    $self->formlink($1, 'formlink', $2) #ige
    and return 1;
  $$rpart =~ s#formlink\[(\w+)\]# $self->formlink($1, 'formlink', undef) #ige
    and return 1;
  $$rpart =~ s#filelink\[\s*(\w+)\s*\|([^\]\[]+)\]# $self->filelink($1, $2) #ige
      and return 1;
  $$rpart =~ s#filelink\[\s*(\w+)\s*\]# $self->filelink($1) #ige
      and return 1;
  $$rpart =~ s#popimage\[([^\[\]]+)\]# $self->popimage($1) #ige
    and return 1;

  return $self->SUPER::replace($rpart);
}

sub formlink {
  my ($self, $id, $type, $text, $target) = @_;

  my $cfg = $self->{gen}{cfg};
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

  return $self->{gen}{cfg}->entry("$id form", 'title', "Send us a comment");
}

sub remove_popimage {
  my ($self, $args) = @_;

  my ($image1, $image2, $align, $style) = split /\|/, $args;

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

sub remove_filelink {
  my ($self, $fileid, $text) = @_;

  my ($file) = grep $_->{name} eq $fileid, @{$self->{files}}
    or return "** unknown file $fileid **";

  return defined $text ? $text : $file->{displayName};
}

sub remove {
  my ($self, $rpart) = @_;

  $$rpart =~ s#gimage\[([^\]\[]+)\]##ig
    and return 1;
  $$rpart =~ s#popdoclink\[(\w+)\|([^\]\[]*)\]#$2#ig
    and return 1;
  $$rpart =~ s#popdoclink\[(\w+)\]# $self->remove_doclink($1) #ige
    and return 1;
  $$rpart =~ s#doclink\[(\w+)\|([^\]\[]*)\]#$2#ig
    and return 1;
  $$rpart =~ s#doclink\[(\w+)\]# $self->remove_doclink($1) #ige
    and return 1;

  $$rpart =~ s#popformlink\[(\w+)\|([^\]\[]*)\]#$2#ig
    and return 1;
  $$rpart =~ s#popformlink\[(\w+)\]# $self->remove_formlink($1) #ige
    and return 1;

  $$rpart =~ s#filelink\[\s*(\w+)\s*\|([^\]\[]+)\]# $self->remove_filelink($1, $2) #ige
      and return 1;
  $$rpart =~ s#filelink\[\s*(\w+)\s*\]# $self->remove_filelink($1) #ige
      and return 1;

  $$rpart =~ s#formlink\[(\w+)\|([^\]\[]*)\]#$2#ig
    and return 1;
  $$rpart =~ s#formlink\[(\w+)\]# $self->remove_formlink($1) #ige
    and return 1;
  $$rpart =~ s#popimage\[([^\[\]]+)\]# $self->remove_popimage($1) #ige
    and return 1;
  
}

sub tag_class {
  my ($self, $type) = @_;

  my $default = $type eq 'p' ? '' : $type;

  return $self->{gen}{cfg}->entry('body class', $type, $default);
}

1;
