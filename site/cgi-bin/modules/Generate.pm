package Generate;
use strict;
use Articles;
use CGI ();
use Constants qw(%EXTRA_TAGS $IMAGEDIR $LOCAL_FORMAT $TMPLDIR $BODY_EMBED 
                 $EMBED_MAX_DEPTH);

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

sub _make_hr {
  my ($width, $height) = @_;
  my $tag = "<hr";
  $tag .= qq!width="$width"! if length $width;
  $tag .= qq!height="$height"! if length $height;
  $tag .= ">";
  return $tag;
}

# produces a table, possibly with options for the <table> and <tr> tags
sub _make_table {
  my ($options, $text) = @_;
  my $tag = "<table";
  my $cellend = '';
  my $cellstart = '';
  if ($options =~ /=/) {
    $tag .= " " . $options;
  }
  elsif ($options =~ /\S/) {
    $options =~ s/\s+$//;
    my ($width, $bg, $pad, $fontsz, $fontface) = split /\|/, $options;
    for ($width, $bg, $pad, $fontsz, $fontface) {
      $_ = '' unless defined;
    }
    $tag .= qq! width="$width"! if length $width;
    $tag .= qq! bgcolor="$bg"! if length $bg;
    $tag .= qq! cellpadding="$pad"! if length $pad;
    if (length $fontsz || length $fontface) {
      $cellstart = qq!<font!;
      $cellstart .= qq! size="$fontsz"! if length $fontsz;
      $cellstart .= qq! face="$fontface"! if length $fontface;
      $cellstart .= qq!>!;
      $cellend = "</font>";
    }
  }
  $tag .= ">";
  my @rows = split '\n', $text;
  my $maxwidth = 0;
  for my $row (@rows) {
    my ($opts, @cols) = split /\|/, $row;
    $tag .= "<tr";
    if ($opts =~ /=/) {
      $tag .= " ".$opts;
    }
    $tag .= "><td>$cellstart".join("$cellend</td><td>$cellstart", @cols)
      ."$cellend</td></tr>";
  }
  $tag .= "</table>";
  return $tag;
}

# make a UL
sub _format_bullets {
  my ($text) = @_;
  $text =~ s/^\s+|\s+$//g;
  my @points = split /\*\*/, $text;
  shift @points if @points and $points[0] eq '';
  return '' unless @points;
  return "<ul><li>".join("<li>", @points)."</ul>";
}

# make a OL
sub _format_ol {
  my ($text) = @_;
  $text =~ s/^\s+|\s+$//g;
  my @points = split /##/, $text;
  shift @points if @points and $points[0] eq '';
  return '' unless @points;
  return "<ol><li>".join("<li>", @points)."</ol>";
}

# raw html - this has some limitations
# the input text has already been escaped, so we need to unescape it
# too bad if you want [] in your html (but you can use entities)
sub _make_html {
  return CGI::unescapeHTML($_[0]);
}

sub _embed_low {
  my ($self, $acts, $articles, $what, $template, $maxdepth) = @_;

  $maxdepth = $self->{maxdepth} 
    if !$maxdepth || $maxdepth > $self->{maxdepth};
  #if ($self->{depth}) {
  #  print STDERR "Embed depth $self->{depth}\n";
  #}
  if ($self->{depth} > $self->{maxdepth}) {
    return "** too many embedding levels **";
  }

  my $id;
  if ($what !~ /^\d+$/) {
    # not an article id, assume there's an article here we can use
    $id = $acts->{$what} && $acts->{$what}->('id');
    unless ($id =~ /^\d+$/) {
      # save it for later
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
      $@ and return "** Cannot load generator $embed->{generator} for article $id **";
      $gen = $embed->{generator}->new(admin=>$self->{admin});
    }

    # a rare appropriate use of local
    local $gen->{depth} = $self->{depth}+1;
    local $gen->{maxdepth} = $maxdepth;
    $template = "" if defined($template) && $template eq "-";
    return $gen->embed($embed, $articles, $template);
  }
  else {
    return "** Cannot find article $id to be embedded **";
  }
}

sub _body_embed {
  my ($self, $acts, $articles, $which, $template) = @_;

  my $text = $self->_embed_low($acts, $articles, $which, $template);

  return $text;
}

# replace markup, insert img tags
sub format_body {
  my ($self, $acts, $articles, $body, $imagePos, @images)  = @_;

  return substr($body, 6) if $body =~ /^<html>/i;

  # clean up any possible existing markup
  $body = CGI::escapeHTML($body);
  
  # I considered replacing these with single character codes and replacing
  # them later with the tags, to avoid having to check for the middle of 
  # tag in the image tag insertion code
  #
  # This wouldn't work because we still need to do the entity substitution
  # before


  # originally the following was just one big loop of replacements, but
  # some tags are a little more complex
  # This needs a real parser

  my $out = '';
  for my $part (split /((?:html\[(?:[^\[\]]*(?:(?:\[[^\[\]]*\])[^\[\]]*)*)\])
			|embed\[(?:[^,\[\]]*)(?:,(?:[^,\[\]]*))?\])/ix, $body) {
    #print STDERR "Part is $part\n";
    if ($part =~ /^html\[([^\[\]]*(?:(?:\[[^\[\]]*\])[^\[\]]*)*)\]$/i) {
      $out .= _make_html($1);
    }
    elsif ($part =~ /^embed\[([^,\[\]]*),([^,\[\]]*)\]$/i) {
      $out .= $self->_body_embed($acts, $articles, $1, $2);
    }
    elsif ($part =~ /^embed\[([^,\[\]]*)\]$/i) {
      $out .= $self->_body_embed($acts, $articles, $1, "")
    }
    else {
      my $match;
    TRY: while (1) {
	$match = 0;
	$LOCAL_FORMAT and $LOCAL_FORMAT->body(\$part)
	  and next TRY;
	$part =~ s#a\[([^,\]\[]+),([^\]\[]+)\]#<a href="$1">$2</a>#ig
	  and next TRY;
	$part =~ s#link\[([^|\]\[]+)\|([^\]\[]+)\]#<a href="$1">$2</a>#ig
	  and next TRY;
	$part =~ s#b\[([^\]\[]+)\]#<b>$1</b>#ig
	  and next TRY;
	$part =~ s#i\[([^\]\[]+)\]#<i>$1</i>#ig
	  and next TRY;
	$part =~ s#align\[([^|\]\[]+)\|([^\]\[]+)\]#<div align="$1">$2</div>#ig
	  and next TRY;
	$part =~ s#font\[([^|\]\[]+)\|([^\]\[]+)\]#<font size="$1">$2</font>#ig
	  and next TRY;
	$part =~ s#hr\[([^|\]\[]*)\|([^\]\[]*)\]#_make_hr($1, $2)#ieg
	  and next TRY;
	$part =~ s#hr\[([^|\]\[]*)\]#_make_hr($1, '')#ieg
	  and next TRY;
	$part =~ s#anchor\[([^|\]\[]*)\]#<a name="$1"></a>#ig
	  and next TRY;
	$part =~ s#table\[([^\n\[\]]*)\n([^\[\]]+)\n\s*\]#_make_table($1, $2)#ieg
	  and next TRY;
	$part =~ s#table\[([^\]\[]+)\|([^\]\[|]+)\]#_make_table($1, "|$2")#ieg
	  and next TRY;
	$part =~ s#((?:\*\*[^\n]+\n[^\S\n]*)+)#_format_bullets($1)#eg
	  and next TRY;
	$part =~ s!((?:##[^\n]+\n[^\S\n]*)+)!_format_ol($1)!eg
	  and next TRY;
	$part =~ s#fontcolor\[([^|\]\[]+)\|([^\]\[]+)\|([^\]\[]+)\]#<font size="$1" color="$2">$3</font>#ig
	  and next TRY;
	$part =~ s#indent\[([^\]\[]+)\]#<ul>$1</ul>#ig
	  and next TRY;
	$part =~ s#center\[([^\]\[]+)\]#<center>$1</center>#ig
	  and next TRY;
	$part =~ s#hrcolor\[([^|\]\[]+)\|([^\]\[]+)\|([^\]\[]+)\]#<table width="$1" height="$2" border="0" bgcolor="$3" cellpadding="0" cellspacing="0"><tr><td><img src="/images/trans_pixel.gif" width="1" height="1"></td></tr></table>#ig
	  and next TRY;
	
	last;
      }
      $part =~ s/\n([ \r]*\n)+/<p>/g;
      $part =~ s/\n/<br>/g;
      $out .= $part;
    }
  }
  $body = $out;

  if (@images) {
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
    if ($imagePos =~ /t/) {
      # inserting the image tags moves character positions around
      # so we need the temp buffer
      my $output = '';
      for my $image (@images) {
	# adjust to make sure this isn't in the middle of a tag or entity
	my $pos = $self->adjust_for_html($body, $incr);

	# assuming 5.005_03 would make this simpler, but <sigh>
	$output .= <<IMG;
<img src="/images/$image->{image}" width="$image->{width}" height="$image->{height}"
alt="$image->{alt}" align="$align" hspace="10" vspace="10">
IMG
	$output .= substr($body, 0, $pos);
	substr($body, 0, $pos) = '';
	$align = $align eq 'right' ? 'left' : 'right';
      }
      $body = $output . $body; # don't forget the rest of it
    }
    else {
      # work from the end
      my $pos = $len;
      for my $image (@images) {
	my $workpos = $self->adjust_for_html($body, $pos);;

	substr($body, $workpos, 0) = <<IMG;
<img src="/images/$image->{image}" width="$image->{width}" height="$image->{height}"
alt="$image->{alt}" align="$align" hspace="10" vspace="10">
IMG
	$pos -= $incr;
	$align = $align eq 'right' ? 'left' : 'right';
      }

    }

  }

  return make_entities($body);
}

sub embed {
  my ($self, $article, $articles, $template) = @_;
  
  $template = $article->{template}
    unless defined($template) && $template =~ /\S/;

  open SOURCE, "< $TMPLDIR$template"
    or die "Cannot open template $template: $!";
  my $html = do { local $/; <SOURCE> };
  close SOURCE;

  # the template will hopefully contain <:embed start:> and <:embed end:>
  # tags
  # otherwise pull out the body content
  if ($html =~ /<:\s*embed\s*start\s*:>(.*)<:\s*embed\s*end\s*:>/s
     || $html =~ m"<\s*body[^>]*>(.*)<\s*/\s*body>"s) {
    $html = $1;
  }
  return $self->generate_low($html, $article, $articles, 1);
}

sub baseActs {
  my ($self, $articles, $acts, $embedded) = @_;

  # used to generate the side menu
  my $section_index = -1;
  my @sections = $articles->listedChildren(-1);
    #sort { $a->{displayOrder} <=> $b->{displayOrder} } 
    #grep $_->{listed}, $articles->sections;
  my $subsect_index = -1;
  my @subsections; # filled as we move through the sections
  my @level3; # filled as we move through the subsections
  my $level3_index = -1;

  my %extras = %EXTRA_TAGS;
  for my $key (keys %extras) {
    unless (ref $extras{$key}) {
      my $data = $extras{$key};
      $extras{$key} = sub { $data };
    }
  }

  return 
    (
     %extras,

     # for embedding the content from children and other sources
     ifEmbedded=> sub { $embedded },
     embed => sub {
       my ($what, $template) = split ' ', $_[0];
       return $self->_embed_low($acts, $articles, $what, $template);
     },
     ifCanEmbed=> sub { $self->{depth} <= $self->{maxdepth} },

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
       return CGI::escapeHTML($sections[$section_index]{$_[0]});
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
       return $subsections[$subsect_index]{$_[0]};
     },
     ifLevel2 => 
     sub {
       return scalar @subsections;
     },
     
     # possibly level3 items
     iterate_level3 => sub {
       return ++$level3_index < @level3;
     },
     level3 => sub { CGI::escapeHTML($level3[$level3_index]{$_[0]}) },
     ifLevel3 => sub { scalar @level3 },

     # generate an admin or link url, depending on admin state
     url=>
     sub {
       my $name = shift;
       my $item = $self->{admin} ? 'admin' : 'link';
       $acts->{$name} or return "<:url $name:>";
       return $acts->{$name}->($item);
     },
     money=>
     sub {
       my ($func, $rest) = split ' ', $_[0], 2;
       $rest = '' unless defined $rest;
       if (!$acts->{$func}) {
	 #print STDERR "money used on $func which doesn't exist\n";
	 return "<: money $func $rest :>";
       }
       my $value = $acts->{$func}->($rest);
       unless (defined $value) {
	 print STDERR "money used on $func which returned undef\n";
	 return "<: money $func $rest :>";
       }
       return sprintf("%.2f", $value/100);
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
         return CGI::escapeHTML($text);
       }
     },
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
  my $match;
  do {
    $match = 0;
    $LOCAL_FORMAT and $LOCAL_FORMAT->clean(\$body)
      and ++$match;
    $body =~ s#a\[([^,\]\[]+),([^\]\[]+)\]#$2#ig
      and ++$match;
    $body =~ s#link\[([^|\]\[]+)\|([^\]\[]+)\]#$2#ig
      and ++$match;
    $body =~ s#[bi]\[([^\]\[]+)\]#$1#ig
      and ++$match;
    $body =~ s#align\[([^|\]\[]+)\|([^\]\[]+)\]#$2#ig
      and ++$match;
    $body =~ s#font\[([^|\]\[]+)\|([^\]\[]+)\]#$2#ig
      and ++$match;
    $body =~ s#hr\[([^|\]\[]*)\|([^\]\[]*)\]##ieg
      and ++$match;
    $body =~ s#hr\[([^|\]\[]*)\]##ieg
      and ++$match;
    $body =~ s#anchor\[([^|\]\[]*)\]##ig
      and ++$match;
    $body =~ s#table\[([^\n\[\]]*)\n([^\[\]]+)\n\s*\]#_cleanup_table($1, $2)#ieg
      and ++$match;
    $body =~ s#table\[([^\]\[]+)\|([^\]\[|]+)\]#_cleanup_table($1, "|$2")#ieg
      and ++$match;
    $body =~ s#\*\*([^\n]+)#$1#eg
      and ++$match;
    $body =~ s!##([^\n]+)!$1!eg
      and ++$match;
    $body =~ s#fontcolor\[([^|\]\[]+)\|([^\]\[]+)\|([^\]\[]+)\]#$3#ig
      and ++$match;
    $body =~ s#(?:indent|center)\[([^\]\[]+)\]#$1#ig
      and ++$match;
    $body =~ s#hrcolor\[([^|\]\[]+)\|([^\]\[]+)\|([^\]\[]+)\]##ig
      and ++$match;
  } while ($match);

  my @found = find_terms(\$body, $case_sensitive, @terms);

  my @reterms = @terms;
  for (@reterms) {
    tr/ / /s;
    $_ = quotemeta;
    s/\s+/\\s+/g;
  }
  # do a reverse sort so that the longer terms (and composite
  # terms) are replaced first
  my $re_str = join("|", reverse sort @reterms);
  my $re = $case_sensitive ? qr/\b($re_str)\b/ : qr/\b($re_str)\b/i;

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

# make whatever text $body points at safe for summarizing by removing most
# block level formatting
sub remove_block {
  my ($self, $body) = @_;

  my $match;
  do {{
    $match = 0;
    $LOCAL_FORMAT and $LOCAL_FORMAT->clean($body)
      and ++$match;
    $$body =~ s#a\[([^,\]\[]+),([^\]\[]+)\]#$2#ig
      and ++$match;
    $$body =~ s#link\[([^|\]\[]+)\|([^\]\[]+)\]#$2#ig
      and ++$match;
    $$body =~ s#([bi])\[([^\]\[]+)\]#$1\001$2\002#ig
      and ++$match;
    $$body =~ s#align\[([^|\]\[]+)\|([^\]\[]+)\]#$2#ig
      and ++$match;
    $$body =~ s#font\[([^|\]\[]+)\|([^\]\[]+)\]#$2#ig
      and ++$match;
    $$body =~ s#hr\[([^|\]\[]*)\|([^\]\[]*)\]##ig
      and ++$match;
    $$body =~ s#hr\[([^|\]\[]*)\]##ig
      and ++$match;
    $$body =~ s#anchor\[([^|\]\[]*)\]##ig
      and ++$match;
    $$body =~ s#table\[([^\n\[\]]*)\n([^\[\]]+)\n\s*\]#_cleanup_table($1, $2)#ieg
      and ++$match;
    $$body =~ s#table\[([^\]\[]+)\|([^\]\[|]+)\]#_cleanup_table($1, "|$2")#ieg
      and ++$match;
    $$body =~ s#\*\*([^\n]+)#$1#g
      and ++$match;
    $$body =~ s!##([^\n]+)!$1!g
      and ++$match;
    $$body =~ s#fontcolor\[([^|\]\[]+)\|([^\]\[]+)\|([^\]\[]+)\]#$3#ig
      and ++$match;
    $$body =~ s#(?:indent|center)\[([^\]\[]+)\]#$1#ig
      and ++$match;
    $$body =~ s#hrcolor\[([^|\]\[]+)\|([^\]\[]+)\|([^\]\[]+)\]##ig
      and ++$match;
  }} while ($match);
  1 while $$body =~ s#([bi])\001([^\001\002]*)\002#$1\[$2\]#ig;
  
}

1;

__END__

=head1 NAME

Generate - provides base Squirel::Template actions for use in generating
pages.

=head1 SYNOPSIS

=head1 DESCRIPTION

This is probably better documented in L<templates>.

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
I<maxdepth> without setting the template.)

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
