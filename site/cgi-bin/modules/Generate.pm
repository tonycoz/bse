package Generate;
use strict;
use Articles;
use Constants qw($IMAGEDIR $LOCAL_FORMAT $BODY_EMBED 
                 $EMBED_MAX_DEPTH $HAVE_HTML_PARSER);
use DevHelp::Tags;
use DevHelp::HTML;
use BSE::Util::Tags;
use BSE::CfgInfo qw(custom_class);
use BSE::Util::Iterate;

my $excerptSize = 300;

sub new {
  my ($class, %opts) = @_;
  $opts{maxdepth} = $EMBED_MAX_DEPTH unless exists $opts{maxdepth};
  $opts{depth} = 0 unless $opts{depth};
  return bless \%opts, $class;
}

# replace commonly used characters
# like MS dumb-quotes
# unfortunately some browsers^W^Wnetscape don't support the entities yet <sigh>
sub make_entities {
  my $text = shift;

  $text =~ s/\226/-/g; # "--" looks ugly
  $text =~ s/\222/'/g;
  $text =~ s/\221/`/g;
  $text =~ s/\&#8217;/'/g;

  return $text;
}

sub summarize {
  my ($self, $articles, $text, $acts, $length) = @_;

  # remove any block level formatting
  $self->remove_block($articles, $acts, \$text);

  $text =~ tr/\n\r / /s;

  if (length $text > $length) {
    $text = substr($text, 0, $length);
    $text =~ s/\s+\S+$//;

    # roughly balance [ and ]
    my $temp = $text;
    1 while $temp =~ s/\s\[[^\]]*\]//; # eliminate matched
    my $count = 0;
    ++$count while $temp =~ s/\w\[[^\]]*$//; # count unmatched

    $text .= ']' x $count;
    $text .= '...';
  }

  # the formatter now adds <p></p> around the text, but we don't
  # want that here
  my $result = $self->format_body({}, $articles, $text, 'tr', 1, 0);
  $result =~ s!<p>|</p>!!g;

  return $result;
}

# attempts to move the given position forward if it's within a HTML tag,
# entity or just a word
sub adjust_for_html {
  my ($self, $text, $pos) = @_;

  # advance if in a tag
  return $pos + length $1 
    if substr($text, 0, $pos) =~ /<[^<>]*$/
      && substr($text, $pos) =~ /^([^<>]*>)/;
  return $pos + length $1
    if substr($text, 0, $pos) =~ /&[^;&]*$/
      && substr($text, $pos) =~ /^([^;&]*;)/;
  return $pos + length $1
    if $pos <= length $text
      && substr($text, $pos-1, 1) =~ /\w$/
      && substr($text, $pos) =~ /^(\w+)/;

  return $pos;
}

# sub _make_hr {
#   my ($width, $height) = @_;
#   my $tag = "<hr";
#   $tag .= qq!width="$width"! if length $width;
#   $tag .= qq!height="$height"! if length $height;
#   $tag .= " />";
#   return $tag;
# }

# # produces a table, possibly with options for the <table> and <tr> tags
# sub _make_table {
#   my ($options, $text) = @_;
#   my $tag = "<table";
#   my $cellend = '';
#   my $cellstart = '';
#   if ($options =~ /=/) {
#     $tag .= " " . $options;
#   }
#   elsif ($options =~ /\S/) {
#     $options =~ s/\s+$//;
#     my ($width, $bg, $pad, $fontsz, $fontface) = split /\|/, $options;
#     for ($width, $bg, $pad, $fontsz, $fontface) {
#       $_ = '' unless defined;
#     }
#     $tag .= qq! width="$width"! if length $width;
#     $tag .= qq! bgcolor="$bg"! if length $bg;
#     $tag .= qq! cellpadding="$pad"! if length $pad;
#     if (length $fontsz || length $fontface) {
#       $cellstart = qq!<font!;
#       $cellstart .= qq! size="$fontsz"! if length $fontsz;
#       $cellstart .= qq! face="$fontface"! if length $fontface;
#       $cellstart .= qq!>!;
#       $cellend = "</font>";
#     }
#   }
#   $tag .= ">";
#   my @rows = split '\n', $text;
#   my $maxwidth = 0;
#   for my $row (@rows) {
#     my ($opts, @cols) = split /\|/, $row;
#     $tag .= "<tr";
#     if ($opts =~ /=/) {
#       $tag .= " ".$opts;
#     }
#     $tag .= "><td>$cellstart".join("$cellend</td><td>$cellstart", @cols)
#       ."$cellend</td></tr>";
#   }
#   $tag .= "</table>";
#   return $tag;
# }

# # make a UL
# sub _format_bullets {
#   my ($text) = @_;

#   $text =~ s/^\s+|\s+$//g;
#   my @points = split /(?:\r?\n)?\*\*\s*/, $text;
#   shift @points if @points and $points[0] eq '';
#   return '' unless @points;
#   for my $point (@points) {
#     $point =~ s!\n$!<br /><br />!;
#   }
#   return "<ul><li>".join("<li>", @points)."</ul>";
# }

# # make a OL
# sub _format_ol {
#   my ($text) = @_;
#   $text =~ s/^\s+|\s+$//g;
#   my @points = split /(?:\r?\n)?##\s*/, $text;
#   shift @points if @points and $points[0] eq '';
#   return '' unless @points;
#   for my $point (@points) {
#     #print STDERR  "point: ",unpack("H*", $point),"\n";
#     $point =~ s!\n$!<br /><br />!;
#   }
#   return "<ol><li>".join("<li>", @points)."</ol>";
# }

# raw html - this has some limitations
# the input text has already been escaped, so we need to unescape it
# too bad if you want [] in your html (but you can use entities)
sub _make_html {
  return unescape_html($_[0]);
}

sub _embed_low {
  my ($self, $acts, $articles, $what, $template, $maxdepth, $templater) = @_;

  $maxdepth = $self->{maxdepth} 
    if !$maxdepth || $maxdepth > $self->{maxdepth};
  #if ($self->{depth}) {
  #  print STDERR "Embed depth $self->{depth}\n";
  #}
  if ($self->{depth} > $self->{maxdepth}) {
    if ($self->{maxdepth} == $EMBED_MAX_DEPTH) {
      return "** too many embedding levels **";
    }
    else {
      return '';
    }
  }

  my $id;
  if ($what !~ /^\d+$/) {
    # not an article id, assume there's an article here we can use
    $id = $acts->{$what} && $templater->perform($acts, $what, 'id');
    unless ($id && $id =~ /^\d+$/) {
      # save it for later
      defined $template or $template = "-";
      return "<:embed $what $template $maxdepth:>";
    }
  }
  else {
    $id = $what;
  }
  my $embed = $articles->getByPkey($id);
  if ($embed) {
    my $gen = $self;
    if (ref($self) ne $embed->{generator}) {
      my $genname = $embed->{generator};
      $genname =~ s#::#/#g; # broken on MacOS I suppose
      $genname .= ".pm";
      eval {
	require $genname;
      };
      if ($@) {
	print STDERR "Cannot load generator $embed->{generator}: $@\n";
	return "** Cannot load generator $embed->{generator} for article $id **";
      }
      my $top = $self->{top} || $embed;
      $gen = $embed->{generator}->new(admin=>$self->{admin}, cfg=>$self->{cfg},
				      request=>$self->{request}, top=>$top);
    }

    # a rare appropriate use of local
    # it's a pity that it's broken before 5.8
    #local $gen->{depth} = $self->{depth}+1;
    #local $gen->{maxdepth} = $maxdepth;
    #$template = "" if defined($template) && $template eq "-";
    #return $gen->embed($embed, $articles, $template);

    my $olddepth = $gen->{depth};
    $gen->{depth} = $self->{depth}+1;
    my $oldmaxdepth = $gen->{maxdepth};
    $gen->{maxdepth} = $maxdepth;
    $template = "" if defined($template) && $template eq "-";
    my $result = $gen->embed($embed, $articles, $template);
    $gen->{depth} = $olddepth;
    $gen->{maxdepth} = $oldmaxdepth;

    return $result;
  }
  else {
    return "** Cannot find article $id to be embedded **";
  }
}

sub _body_embed {
  my ($self, $acts, $articles, $which, $template, $maxdepth) = @_;

  my $text = $self->_embed_low($acts, $articles, $which, $template, $maxdepth);

  return $text;
}

sub _make_img {
  my ($args, $imagePos, $images) = @_;

  my ($index, $align, $url) = split /\|/, $args, 3;
  my $text = '';
  if ($index >=1 && $index <= @$images) {
# I considered this
#      if (!$align) {
#        $align = $$imagePos =~ /r/ ? 'right' : 'left';
#        $$imagePos =~ tr/rl/lr/; # I wonder
#      }
    my $im = $images->[$index-1];
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
  return $text;
}

# replace markup, insert img tags
sub format_body {
  my ($self, $acts, $articles, $body, $imagePos, $abs_urls, 
      $auto_images, $templater, @images)  = @_;

  return substr($body, 6) if $body =~ /^<html>/i;

  require BSE::Formatter;

  my $formatter = BSE::Formatter->new($self, $acts, $articles,
				      $abs_urls, \$auto_images,
				      \@images, $templater);

  $body = $formatter->format($body);

  # we don't format named images
  @images = grep $_->{name} eq '', @images;
  if ($auto_images && @images) {
    # the first image simply goes where we're told to put it
    # the imagePos is [tb][rl] (top|bottom)(right|left)
    my $align = $imagePos =~ /r/ ? 'right' : 'left';

    # Offset the end a bit so we don't get an image hanging as obviously
    # off the end.
    # Numbers determined by trial - it can still look pretty rough.
    my $len = length $body;
    if ($len > 1000) {
      $len -= 500; 
    }
    elsif ($len > 800) {
      $len -= 200;
    }

    #my $incr = @images > 1 ? 2*$len / (2*@images+1) : 0;
    my $incr = $len / @images;
    # inserting the image tags moves character positions around
    # so we need the temp buffer
    if ($imagePos =~ /b/) {
      @images = reverse @images;
      if (@images % 2 == 0) {
	# starting at the bottom, swap it around
	$align = $align eq 'right' ? 'left' : 'right';
      }
    }
    my $output = '';
    for my $image (@images) {
      # adjust to make sure this isn't in the middle of a tag or entity
      my $pos = $self->adjust_for_html($body, $incr);
      
      # assuming 5.005_03 would make this simpler, but <sigh>
      my $img = qq!<img src="/images/$image->{image}"!
	.qq! width="$image->{width}" height="$image->{height}" border="0"!
	  .qq! alt="$image->{alt}" align="$align" hspace="10" vspace="10" />!;
      if ($image->{url}) {
	$img = qq!<a href="$image->{url}">$img</a>!;
      }
      $output .= $img;
      $output .= substr($body, 0, $pos);
      substr($body, 0, $pos) = '';
      $align = $align eq 'right' ? 'left' : 'right';
    }
    $body = $output . $body; # don't forget the rest of it
  }
  
  return make_entities($body);
}

sub embed {
  my ($self, $article, $articles, $template) = @_;
  
  if (defined $template && $template =~ /\$/) {
    $template =~ s/\$/$article->{template}/;
  }
  else {
    $template = $article->{template}
      unless defined($template) && $template =~ /\S/;
  }

  my $html = BSE::Template->get_source($template, $self->{cfg});

  # the template will hopefully contain <:embed start:> and <:embed end:>
  # tags
  # otherwise pull out the body content
  if ($html =~ /<:\s*embed\s*start\s*:>(.*)<:\s*embed\s*end\s*:>/s
     || $html =~ m"<\s*body[^>]*>(.*)<\s*/\s*body>"s) {
    $html = $1;
  }
  return $self->generate_low($html, $article, $articles, 1);
}

sub iter_kids_of {
  my ($args, $acts, $name, $templater) = @_;

  my @ids = map { split } DevHelp::Tags->get_parms($args, $acts, $templater);
  for my $id (@ids) {
    unless ($id =~ /^\d+$|^-1$/) {
      $id = $templater->perform($acts, $id, "id");
    }
  }
  @ids = grep /^\d+$|^-1$/, @ids;
  map Articles->listedChildren($_), @ids;
}

sub iter_all_kids_of {
  my ($args, $acts, $name, $templater) = @_;

  my @ids = map { split } DevHelp::Tags->get_parms($args, $acts, $templater);
  for my $id (@ids) {
    unless ($id =~ /^\d+$|^-1$/) {
      $id = $templater->perform($acts, $id, "id");
    }
  }
  @ids = grep /^\d+$|^-1$/, @ids;
  map Articles->all_visible_kids($_), @ids;
}

sub iter_inlines {
  my ($args, $acts, $name, $templater) = @_;

  my @ids = map { split } DevHelp::Tags->get_parms($args, $acts, $templater);
  for my $id (@ids) {
    unless ($id =~ /^\d+$/) {
      $id = $templater->perform($acts, $id, "id");
    }
  }
  @ids = grep /^\d+$/, @ids;
  map Articles->getByPkey($_), @ids;
}

sub iter_gimages {
  my ($self, $args) = @_;

  unless ($self->{gimages}) {
    require Images;
    my @gimages = Images->getBy(articleId => -1);
    my %gimages = map { $_->{name} => $_ } @gimages;
    $self->{gimages} = \%gimages;
  }

  my @gimages = 
    sort { $a->{name} cmp $b->{name} } values %{$self->{gimages}};
  if ($args =~ m!^named\s+/([^/]+)/$!) {
    my $re = $1;
    return grep $_->{name} =~ /$re/i, @gimages;
  }
  else {
    return @gimages;
  }
}

sub admin_tags {
  my ($self) = @_;

  $self->{admin} or return;

  return BSE::Util::Tags->secure($self->{request});
}

sub baseActs {
  my ($self, $articles, $acts, $article, $embedded) = @_;

  # used to generate the side menu
  my $section_index = -1;
  my @sections = $articles->listedChildren(-1);
    #sort { $a->{displayOrder} <=> $b->{displayOrder} } 
    #grep $_->{listed}, $articles->sections;
  my $subsect_index = -1;
  my @subsections; # filled as we move through the sections
  my @level3; # filled as we move through the subsections
  my $level3_index = -1;

  my $cfg = $self->{cfg} || BSE::Cfg->new;
  my %extras = $cfg->entriesCS('extra tags');
  for my $key (keys %extras) {
    # follow any links
    my $data = $cfg->entryVar('extra tags', $key);
    $extras{$key} = sub { $data };
  }
  my $it = BSE::Util::Iterate->new;
  return 
    (
     %extras,

     custom_class($cfg)->base_tags($articles, $acts, $article, $embedded, $cfg),
     $self->admin_tags(),
     BSE::Util::Tags->static($acts, $self->{cfg}),
     # for embedding the content from children and other sources
     ifEmbedded=> sub { $embedded },
     embed => sub {
       my ($args, $acts, $name, $templater) = @_;
       my ($what, $template, $maxdepth) = split ' ', $args;
       undef $maxdepth if defined $maxdepth && $maxdepth !~ /^\d+/;
       return $self->_embed_low($acts, $articles, $what, $template, $maxdepth, $templater);
     },
     ifCanEmbed=> sub { $self->{depth} <= $self->{maxdepth} },

     summary =>
     sub {
       my ($which, $acts, $name, $templater) = @_;
       $which or $which = "child";
       $acts->{$which}
	 or return "<:summary $which Cannot find $which:>";
       my $id = $templater->perform($acts, $which, "id")
	 or return "<:summary $which No id returned :>";
       my $article = $articles->getByPkey($id)
	 or return "<:summary $which Cannot find article $id:>";
       return $self->summarize($articles, $article->{body}, $acts, 
			       $article->{summaryLength})
     },
     ifAdmin => sub { $self->{admin} },
     
     # for generating the side menu
     iterate_level1_reset => sub { $section_index = -1 },
     iterate_level1 => sub {
       ++$section_index;
       if ($section_index < @sections) {
	 #@subsections = grep $_->{listed}, 
	 #  $articles->children($sections[$section_index]->{id});
	 @subsections = grep { $_->{listed} != 2 }
	   $articles->listedChildren($sections[$section_index]->{id});
	 $subsect_index = -1;
	 return 1;
       }
       else {
	 return 0;
       }
     },
     level1 => sub {
       return escape_html($sections[$section_index]{$_[0]});
     },

     # used to generate a list of subsections for the side-menu
     iterate_level2 => sub {
       ++$subsect_index;
       if ($subsect_index < @subsections) {
         @level3 = grep { $_->{listed} != 2 }
           $articles->listedChildren($subsections[$subsect_index]{id});
         $level3_index = -1;
         return 1;
       }
       return 0;
     },
     level2 => sub {
       return escape_html($subsections[$subsect_index]{$_[0]});
     },
     ifLevel2 => 
     sub {
       return scalar @subsections;
     },
     
     # possibly level3 items
     iterate_level3 => sub {
       return ++$level3_index < @level3;
     },
     level3 => sub { escape_html($level3[$level3_index]{$_[0]}) },
     ifLevel3 => sub { scalar @level3 },

     # generate an admin or link url, depending on admin state
     url=>
     sub {
       my ($name, $acts, $func, $templater) = @_;
       my $item = $self->{admin} ? 'admin' : 'link';
       $acts->{$name} or return "<:url $name:>";
       return $templater->perform($acts, $name, $item);
     },
     ifInMenu =>
     sub {
       $acts->{$_[0]} or return 0;
       return $acts->{$_[0]}->('listed') == 1;
     },
     titleImage=>
     sub {
       my ($image, $text) = split ' ', $_[0];
       if (-e $IMAGEDIR."/titles/".$image) {
         return qq!<img src="/images/titles/!.$image .qq!" border=0>!
       }
       else {
         return escape_html($text);
       }
     },
     $it->make_iterator( \&iter_kids_of, 'ofchild', 'children_of' ), 
     $it->make_iterator( \&iter_all_kids_of, 'ofallkid', 'allkids_of' ), 
     $it->make_iterator( \&iter_inlines, 'inline', 'inlines' ),
     gimage => 
     sub {
       my ($name, $align, $rest) = split ' ', $_[0], 3;

       my $im = $self->get_gimage($name)
	 or return '';

       $self->_format_image($im, $align, $rest);
     },
     $it->make_iterator( [ \&iter_gimages, $self ], 'gimagei', 'gimages'),
    );
}

sub find_terms {
  my ($body, $case_sensitive, @terms) = @_;
  
  # locate the terms
  my @found;
  if ($case_sensitive) {
    for my $term (@terms) {
      if ($$body =~ /^(.*?)\Q$term/s) {
	push(@found, [ length($1), $term ]);
      }
    }
  }
  else {
    for my $term (@terms) {
      if ($$body =~ /^(.*?)\Q$term/is) {
	push(@found, [ length($1), $term ]);
      }
    }
  }

  return @found;
}

# this takes the same inputs as _make_table(), but eliminates any
# markup instead
sub _cleanup_table {
  my ($opts, $data) = @_;
  my @lines = split /\n/, $data;
  for (@lines) {
    s/^[^|]*\|//;
    tr/|/ /s;
  }
  return join(' ', @lines);
}

# produce a nice excerpt for a found article
sub excerpt {
  my ($self, $article, $found, $case_sensitive, @terms) = @_;

  my $body = $article->{body};

  # we remove any formatting tags here, otherwise we get wierd table
  # rubbish or other formatting in the excerpt.
  $self->remove_block('Articles', [], \$body);
  1 while $body =~ s/[bi]\[([^\]\[]+)\]/$1/g;

  $body = escape_html($body);

  my @found = find_terms(\$body, $case_sensitive, @terms);

  my @reterms = @terms;
  for (@reterms) {
    tr/ / /s;
    $_ = quotemeta;
    s/\\?\s+/\\s+/g;
  }
  # do a reverse sort so that the longer terms (and composite
  # terms) are replaced first
  my $re_str = join("|", reverse sort @reterms);
  my $re;
  my $cfg = $self->{cfg};
  if ($cfg->entryBool('basic', 'highlight_partial', 1)) {
    $re = $case_sensitive ? qr/\b($re_str)/ : qr/\b($re_str)/i;
  }
  else {
    $re = $case_sensitive ? qr/\b($re_str)\b/ : qr/\b($re_str)\b/i;
  }

  # this used to try searching children as well, but it broke more
  # than it fixed
  if (!@found) {
    # we tried hard and failed
    # return a generic article
    if (length $body > $excerptSize) {
      $body = substr($body, 0, $excerptSize);
      $body =~ s/\S+\s*$/.../;
    }
    $$found = 0;
    return $body;
  }

  # only the first 5
  splice(@found, 5,-1) if @found > 5;
  my $itemSize = $excerptSize / @found;

  # try to combine any that are close
  @found = sort { $a->[0] <=> $b->[0] } @found;
  for my $i (reverse 0 .. $#found-1) {
    if ($found[$i+1][0] - $found[$i][0] < $itemSize) {
      my @losing = @{$found[$i+1]};
      shift @losing;
      push(@{$found[$i]}, @losing);
      splice(@found, $i+1, 1); # remove it
    }
  }

  my $termSize = $excerptSize / @found;
  my $result = '';
  for my $term (@found) {
    my ($pos, @terms) = @$term;
    my $start = $pos - $termSize/2;
    my $part;
    if ($start < 0) {
      $start = 0;
      $part = substr($body, 0, $termSize);
    }
    else {
      $result .= "...";
      $part = substr($body, $start, $termSize);
      $part =~ s/^\w+//;
    }
    if ($start + $termSize < length $body) {
      $part =~ s/\s*\S*$/... /;
    }
    $result .= $part;
  }
  $result =~ s{$re}{<b>$1</b>}ig;
  $$found = 1;

  return $result;
}

sub visible {
  return 1;
}

# # removes any html tags from the supplied text
# sub _strip_html {
#   my ($text) = @_;

#   if ($HAVE_HTML_PARSER) {
#     my $out = '';
#     # don't forget that require is smart
#     require "HTML/Parser.pm";

#     # this may need to detect and skip <script></script> and stylesheets
#     my $ignore_text = 0; # non-zero in a <script></script> or <style></style>
#     my $start_h = 
#       sub {
# 	++$ignore_text if $_[0] eq 'script' or $_[0] eq 'style';
# 	if ($_[0] eq 'img' && $_[1]{alt} && !$ignore_text) {
# 	  $out .= $_[1]{alt};
# 	}
#       };
#     my $end_h = 
#       sub {
# 	--$ignore_text if $_[0] eq 'script' or $_[0] eq 'style';
#       };
#     my $text_h = 
#       sub { 
# 	$out .= $_[0] unless $ignore_text
#       };
#     my $p = HTML::Parser->new( text_h  => [ $text_h,  "dtext" ],
#                                start_h => [ $start_h, "tagname, attr" ],
#                                end_h   => [ $end_h,   "tagname" ]);
#     $p->parse($text);
#     $p->eof();

#     $text = $out;
#   }
#   else {
#     # this won't work for some HTML, but it's a fallback
#     $text =~ s/<[^>]*>//g;
#   }

#   return $text;
# }

# make whatever text $body points at safe for summarizing by removing most
# block level formatting
sub remove_block {
  my ($self, $articles, $acts, $body) = @_;

  require BSE::Formatter;

  my $formatter = BSE::Formatter->new($self, $acts, $articles,
				      1, \0, []);

  $$body = $formatter->remove_format($$body);
}

sub get_gimage {
  my ($self, $name) = @_;

  unless ($self->{gimages}) {
    require Images;
    my @gimages = Images->getBy(articleId => -1);
    my %gimages = map { $_->{name} => $_ } @gimages;
    $self->{gimages} = \%gimages;
  }

  return $self->{gimages}{$name};
}

sub _format_image {
  my ($self, $im, $align, $rest) = @_;

  if ($align && exists $im->{$align}) {
    return escape_html($im->{$align});
  }
  else {
    my $html = qq!<img src="/images/$im->{image}" width="$im->{width}"!
      . qq! height="$im->{height}" alt="! . escape_html($im->{alt})
	     . qq!"!;
    $html .= qq! align="$align"! if $align && $align ne '-';
    unless (defined($rest) && $rest =~ /\bborder=/i) {
      $html .= ' border="0"';
    }
    $html .= " $rest" if defined $rest;
    $html .= qq! />!;
    if ($im->{url}) {
      $html = qq!<a href="$im->{url}">$html</a>!;
    }
    return $html;
  }
}

1;

__END__

=head1 NAME

Generate - provides base Squirel::Template actions for use in generating
pages.

=head1 SYNOPSIS

=head1 DESCRIPTION

This is probably better documented in L<templates.pod>.

=head1 COMMON TAGS

These tags can be used anywhere, including in admin templates.  It's
possible some admin code has been missed, if you find a place where
these cannot be used let us know.


=over

=item kb I<data tag>

Formats the give value in kI<whatevers>.  If you have a number that
could go over 1000 and you want it to use the 'k' metric prefix when
it does, use this tag.  eg. <:kb file sizeInBytes:>

=item date I<data tag>

=item date "I<format>" I<data tag>

Formats a date or date/time value from the database into something
more human readable.  If you don't supply a format then the default
format of "%d-%b-%Y" is used ("20-Mar-2002").

The I<format> is a strftime() format specification, if that means
anything to you.  If it doesn't, each code starts with % and are
replaced as follows:

=over

=item %a

abbreviated weekday name

=item %A

full weekday name

=item %b

abbreviated month name

=item %B

full month name

=item %c

"preferred" date and time representation

=item %d

day of the month as a 2 digit number

=item %H

hour (24-hour clock)

=item %I

hour (12-hour clock)

=item %j

day of year as a 3-digit number

=item %m

month as a 2 digit number

=item %M

minute as a 2 digit number

=item %p

AM or PM or their equivalents

=item %S

seconds as a 2 digit number

=item %U

week number as a 2 digit number (first Sunday as the first day of week 1)

=item %w

weekday as a decimal number (0-6)

=item %W

week number as a 2 digit number (first Monday as the first day of week 1)

=item %x

the locale's appropriate date representation

=item %X

the locale's appropriate time representation

=item %y

2-digit year without century

=item %Y

the full year

=item %Z

time zone name or abbreviation

=item %%

just '%'

=back

Your local strftime() implementation may implement some extensions to
the above, if your server is on a Unix system try running "man
strftime" for more information.

=item bodytext I<data tag>

Formats the text from the given tag in the same way that body text is.

=item ifEq I<data1> I<data2>

Checks if the 2 values are exactly equal.  This is a string
comparison.

The 2 data parameters can either be a tag reference in [], a literal
string inside "" or a single word.

=item ifMatch I<data1> I<data2>

Treats I<data2> as a perl regular expression and attempts to match
I<data1> against it.

The 2 data parameters can either be a tag reference in [], a literal
string inside "" or a single word.

=item cfg I<section> I<key>

=item cfg I<section> I<key> I<default>

Retrieves a value from the BSE configuration file.

If you don't supply a default then a default will be the empty string.

=item release

The release number of BSE.

=back

=head1 TAGS

=over 4

=item ifAdmin

Conditional tag, true if generating in admin mode.

=item iterator ... level1

Iterates over the listed level 1 articles.

=item level1 I<name>

The value of the I<name> field of the current level 1 article.

=item iterator ... level2

Iterates over the listed level 2 children of the current level 1 article.

=item level2 I<name>

The value of the I<name> field of the current level 2 article.

=item ifLevel2 I<name>

Conditional tag, true if the current level 1 article has any listed
level 2 children.

=item iterator ... level3

Iterates over the listed level 3 children of the current level 2 article.

=item level3 I<name>

The value of the I<name> field of the current level 3 article.

=item ifLevel3 I<name>

Conditional tag, true if the current level 2 article has any listed
level 3 children.

=item url I<which>

Returns a link to the specified article .  Due to the way the action
list is built, this can be article types defined in derived classes of
Generate, like the C<parent> article in Generate::Article.

=item money I<data tag>

Formats the given value as a monetary value.  This does not include a
currency symbol.  Internally BSE stores monetary values as integers to
prevent the loss of accuracy inherent in floating point numbers.  You
need to use this tag to display any monetary value.

=item ifInMenu I<which>

Conditional tag, true if the given item can appear in a menu.

=item titleImage I<imagename> I<text>

Generates an IMG tag if the given I<imagename> is in the title image
directory ($IMAGEDIR/titles).  If it doesn't exists, produces the
I<text>.

=item embed I<which>

=item embed I<which> I<template>

=item embed I<which> I<template> I<maxdepth>

=item embed child

Embeds the article specified by which using either the specified
template or the articles template.

In this case I<which> can also be an article ID.

I<template> is a filename relative to the templates directory.  If
this is "-" then the articles template is used (so you can set
I<maxdepth> without setting the template.)  If I<template> contains a
C<$> sign it will be replaced with the name of the original template.

If I<maxdepth> is supplied and is less than the current maximum depth
then it becomes the new maximum depth.  This can be used with ifCanEmbed.

=item embed start ... embed end

Marks the range of text that would be embedded in a parent that used
C<embed child>.

=item ifEmbedded

Conditional tag, true if the current article is being embedded.

=back

=head1 BUGS

Needs more documentation.

=cut
