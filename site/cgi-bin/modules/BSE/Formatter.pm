package BSE::Formatter;
use strict;
use DevHelp::HTML;
use Carp 'confess';

use base 'DevHelp::Formatter';

sub new {
  my ($class, $gen, $acts, $articles, $abs_urls, $rauto_images, $images) = @_;

  my $self = $class->SUPER::new;

  $self->{gen} = $gen;
  $self->{acts} = $acts;
  $self->{articles} = $articles;
  $self->{abs_urls} = $abs_urls;
  $self->{auto_images} = $rauto_images;
  $self->{images} = $images;
  #$self->{level} = $level;

  $self;
}

sub _image {
  my ($self, $im, $align, $url) = @_;

  my $text = qq!<img src="/images/$im->{image}" width="$im->{width}"!
    . qq! height="$im->{height}" alt="! . escape_html($im->{alt}).'"'
      . qq! border="0"!;
  $text .= qq! align="$align"! if $align && $align ne 'center';
  $text .= qq! />!;
  $text = qq!<div align="center">$text</div>!
    if $align && $align eq 'center';
  if (!$url && $im->{url}) {
    $url = $im->{url};
  }
  if ($url) {
    $text = qq!<a href="! . escape_html($url) . qq!">$text</a>!;
  }

  return $text;
}

sub gimage {
  my ($self, $args) = @_;

  my ($name, $align, $url) = split /\|/, $args, 3;
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
  my ($index, $align, $url) = split /\|/, $args, 3;
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
    return $self->_image($im, $align, $url);
  }
  else {
    return '';
  }
}

sub embed {
  my ($self, $name, $templateid, $maxdepth) = @_;

  $self->{gen}->_embed_low($self->{acts}, $self->{articles}, $name,
			   $templateid, $maxdepth);
}

sub doclink {
  my ($self, $id, $title) = @_;
  
  my $admin = $self->{gen}{admin};
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
      return "&#42;&#42; No article name '".escape_html($id)."' in the [articles] section of bse.cfg &#42;&#42;";
    }
    $dispid = "$id ($work)";
    $id = $work;
  }
  my $art = $self->{articles}->getByPkey($id);
  unless ($art) {
    return "&#42;&#42; Cannot find article id $dispid &#42;&#42;";
  }

  # make the URL absolute if necessary
  my $link = $admin ? 'admin' : 'link';
  my $url = $art->{$link};
  if ($self->{abs_urls}) {
    $url = $cfg->entryErr('site', 'url') . $url
      unless $url =~ /^\w+:/;
  }

  unless ($title) {
    $title = escape_html($art->{title});
  }
  
  return qq!<a href="$url">$title</a>!;
}

sub replace {
  my ($self, $rpart) = @_;

  $$rpart =~ s#gimage\[([^\]\[]+)\]# $self->gimage($1) #ige
    and return 1;
  $$rpart =~ s#doclink\[(\w+)\|([^\]\[]+)\]# $self->doclink($1, $2) #ige
    and return 1;
  $$rpart =~ s#doclink\[(\w+)\]# $self->doclink($1) #ige
    and return 1;

  return $self->SUPER::replace($rpart);
}

1;
