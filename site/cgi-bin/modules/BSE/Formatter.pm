package BSE::Formatter;
use strict;
use DevHelp::HTML;

use base 'DevHelp::Formatter';

sub new {
  my ($class, $gen, $acts, $articles, $rauto_images, $images) = @_;

  my $self = $class->SUPER::new;

  $self->{gen} = $gen;
  $self->{acts} = $acts;
  $self->{articles} = $articles;
  $self->{auto_images} = $rauto_images;
  $self->{images} = $images;
  #$self->{level} = $level;

  $self;
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
    $text = qq!<img src="/images/$im->{image}" width="$im->{width}"!
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
  }
  ${$self->{auto_images}} = 0;

  return $text;
}

sub embed {
  my ($self, $name, $templateid, $maxdepth) = @_;

  $self->{gen}->_embed_low($self->{acts}, $self->{articles}, $name,
			   $templateid, $maxdepth);
}

1;
