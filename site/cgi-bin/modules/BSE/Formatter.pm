package BSE::Formatter;
use strict;
use DevHelp::HTML;
use Carp 'confess';

use base 'DevHelp::Formatter';

sub new {
  my ($class, $gen, $acts, $articles, $abs_urls, $rauto_images, $images, $templater) = @_;

  my $self = $class->SUPER::new;

  $self->{gen} = $gen;
  $self->{acts} = $acts;
  $self->{articles} = $articles;
  $self->{abs_urls} = $abs_urls;
  $self->{auto_images} = $rauto_images;
  $self->{images} = $images;
  $self->{templater} = $templater;
  #$self->{level} = $level;

  my $cfg = $gen->{cfg};
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
    if ($style =~ /^\w+$/) {
      $text .= qq! class="$style"!;
    }
    elsif ($style =~ /^\d/) {
      $text .= qq! style="padding: $style"!;
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

  return $self->SUPER::replace($rpart);
}

sub formlink {
  my ($self, $id, $type, $text, $target) = @_;

  my $title = escape_html($self->{gen}{cfg}->entry("$id form", 'title', "Send us a comment"));
  $text ||= $title;

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

  return qq!<a href="/cgi-bin/fmail.pl?form=$id" title="$title"$extras>$text</a>!;
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
  $$rpart =~ s#formlink\[(\w+)\|([^\]\[]*)\]#$2#ig
    and return 1;
  $$rpart =~ s#formlink\[(\w+)\]# $self->remove_formlink($1) #ig
    and return 1;
  
}

sub tag_class {
  my ($self, $type) = @_;

  my $default = $type eq 'p' ? '' : $type;

  return $self->{gen}{cfg}->entry('body class', $type, $default);
}

1;
