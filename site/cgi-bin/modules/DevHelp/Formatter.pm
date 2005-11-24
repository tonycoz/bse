package DevHelp::Formatter;
use strict;
use DevHelp::HTML;
use Carp 'confess';

use constant DEBUG => 0;

sub new {
  my ($class) = @_;

  return bless {}, $class;
}

sub embed {
  '';
}

sub image {
  my ($self, $imagename, $align) = @_;

  return '';
}

sub replace {
}

sub _make_hr {
  my ($width, $height) = @_;
  my $tag = "<hr";
  $tag .= qq! width="$width"! if length $width;
  $tag .= qq! size="$height"! if length $height;
  $tag .= " />";
  return $tag;
}

# produces a table, possibly with options for the <table> and <tr> tags
sub _make_table {
  my ($options, $text) = @_;
  my $tag = "<table";
  my $cellend = '';
  my $cellstart = '';
  if ($options =~ /=/) {
    $tag .= " " . unescape_html($options);
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
      $tag .= " ".unescape_html($opts);
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
  my @points = split /(?:\r?\n)? *\*\*\s*/, $text;
  shift @points if @points and $points[0] eq '';
  return '' unless @points;
  for my $point (@points) {
    $point =~ s!\n$!!
      and $point = "<p>$point</p>";
  }
  return "<ul><li>".join("</li><li>", @points)."</li></ul>";
}

# make a OL
sub _format_ol {
  my ($text, $type, $code) = @_;

  print STDERR "_format_ol(..., $type, $code)\n" if DEBUG;
  print STDERR "text: ",unpack("H*", $text),"\n" if DEBUG;
  $text =~ s/^\s+|\s+$//g;
  $code ||= "##";
  my @points = split /(?:\r?\n)? *$code\s*/, $text;
  shift @points if @points and $points[0] eq '';
  return '' unless @points;
  for my $point (@points) {
    $point =~ s!\n$!!
      and $point = "<p>$point</p>";
  }
  my $ol = "<ol";
  $ol .= qq! type="$type"! if $type;
  $ol .= ">";
  return "$ol<li>".join("</li><li>", @points)."</li></ol>";
}

sub _format_lists {
  my ($text) = @_;

  my $out = '';

  while (length $text) {
    if ($text =~ s!^((?: *\#\#[^\n]+(?:\n|$)\n?[^\S\n]*)+)\n?!!) {
      $out .= _format_ol($1);
    }
    elsif ($text =~ s#^((?: *\*\*[^\n]+(?:\n|$)\n?[^\S\n]*)+)\n?##) {
      $out .= _format_bullets($1);
    }
    elsif ($text =~ s!^((?: *%%[^\n]+(?:\n|$)\n?[^\S\n]*)+)\n?!!) {
      $out .= _format_ol($1, 'a', '%%');
    }
    else {
      $out .= $text;
      $text = '';
    }
  }

  return $out;
}

# raw html - this has some limitations
# the input text has already been escaped, so we need to unescape it
# too bad if you want [] in your html (but you can use entities)
sub _make_html {
  return unescape_html($_[0]);
}

sub _fix_spanned {
  my ($self, $start, $end, $text, $type) = @_;

  if ($type) {
    my $class = $self->tag_class($type);
    if ($class) {
      $start =~ s/>$/ class="$class">/;
    }
  }

  $text =~ s!(\n(?:[ \r]*\n)+)!$end$1$start!g;

  "$start$text$end";
}

sub replace_char {
  my ($self, $rpart) = @_;
  $$rpart =~ s#(acronym|abbr|dfn)\[([^|\]\[]+)\|([^\]\[]+)\|([^\]\[]+)\]#
    $self->_fix_spanned(qq/<$1 class="$3" title="$2">/, "</$1>", $4)#egi
    and return 1;
  $$rpart =~ s#(acronym|abbr|dfn)\[([^|\]\[]+)\|([^\]\[]+)\]#
    $self->_fix_spanned(qq/<$1 title="$2">/, "</$1>", $3)#egi
    and return 1;
  $$rpart =~ s#(acronym|abbr|dfn)\[\|([^\]\[]+)\]#
    $self->_fix_spanned("<$1>", "</$1>", $2)#egi
    and return 1;
  $$rpart =~ s#(acronym|abbr|dfn)\[([^\]\[]+)\]#
    $self->_fix_spanned("<$1>", "</$1>", $2)#egi
    and return 1;
  $$rpart =~ s#bdo\[([^|\]\[]+)\|([^\]\[]+)\]#
    $self->_fix_spanned(qq/<bdo dir="$1">/, "</bdo>", $2)#egi
    and return 1;
  $$rpart =~ s#(strong|em|samp|code|var|sub|sup|kbd|q|b|i|tt)\[([^|\]\[]+)\|([^\]\[]+)\]#
    $self->_fix_spanned(qq/<$1 class="$2">/, "</$1>", $3)#egi
    and return 1;
  $$rpart =~ s#(strong|em|samp|code|var|sub|sup|kbd|q|b|i|tt)\[\|([^\]\[]+)\]#
    $self->_fix_spanned("<$1>", "</$1>", $2)#egi
    and return 1;
  $$rpart =~ s#(strong|em|samp|code|var|sub|sup|kbd|q|b|i|tt)\[([^\]\[]+)\]#
    $self->_fix_spanned("<$1>", "</$1>", $2)#egi
    and return 1;
  $$rpart =~ s#poplink\[([^|\]\[]+)\|([^\]\[]+)\]#
    $self->_fix_spanned(qq/<a href="$1" target="_blank">/, "</a>", $2, 'poplink')#eig
    and return 1;
  $$rpart =~ s#poplink\[([^|\]\[]+)\]#
    $self->_fix_spanned(qq/<a href="$1" target="_blank">/, "</a>", $1, 'poplink')#ieg
    and return 1;
  $$rpart =~ s#link\[([^|\]\[]+)\|([^\]\[]+)\]#
    $self->_fix_spanned(qq/<a href="$1">/, "</a>", $2, 'link')#eig
    and return 1;
  $$rpart =~ s#link\[([^|\]\[]+)\]#
    $self->_fix_spanned(qq/<a href="$1">/, "</a>", $1, 'link')#ieg
    and return 1;
  $$rpart =~ s#font\[([^|\]\[]+)\|([^\]\[]+)\]#
    $self->_fix_spanned(qq/<font size="$1">/, "</font>", $2)#egi
    and return 1;
  $$rpart =~ s#anchor\[([^|\]\[]*)\]#<a name="$1"></a>#ig
    and return 1;
  $$rpart =~ s#fontcolor\[([^|\]\[]+)\|([^\]\[]+)\|([^\]\[]+)\]#
    $self->_fix_spanned(qq/<font size="$1" color="$2">/, "</font>", $3)#egi
    and return 1;
  $$rpart =~ s!(?<=\W)\[([^\]\[]+)\]!&#91;$1&#93;!g
    and return 1;
  
  return 0;
}

sub format {
  my ($self, $body) = @_;

  print STDERR "format(...)\nbody: ",unpack("H*", $body),"\n" if DEBUG;

  if ($body =~ /\n/) {
    $body =~ tr/\r//d;
  }

  $body = $self->escape($body);
  my $out = '';
  for my $part (split /((?:html\[(?:[^\[\]]*(?:(?:\[[^\[\]]*\])[^\[\]]*)*)\])
			|embed\[(?:[^,\[\]]*)(?:,(?:[^,\[\]]*)){0,2}\]
                        |pre\[(?:[^\[\]]*(?:(?:\[[^\[\]]*\])[^\[\]]*)*)\])/ix, $body) {
    #print STDERR "Part is $part\n";
    if ($part =~ /^html\[([^\[\]]*(?:(?:\[[^\[\]]*\])[^\[\]]*)*)\]$/i) {
      $out .= _make_html($1);
    }
    elsif ($part =~ /^embed\[([^,\[\]]*),([^,\[\]]*),([^,\[\]]*)\]$/i) {
      $out .= $self->embed($1, $2, $3);
    }
    elsif ($part =~ /^embed\[([^,\[\]]*),([^,\[\]]*)\]$/i) {
      $out .= $self->embed($1, $2);
    }
    elsif ($part =~ /^embed\[([^,\[\]]*)\]$/i) {
      $out .= $self->embed($1)
    }
    elsif ($part =~ /^pre\[([^\[\]]*(?:(?:\[[^\[\]]*\])[^\[\]]*)*)\]$/i) {
      my $work = $1;
      1 while $self->replace_char(\$work);
      $out .= "<pre>$work</pre>";
    }
    else {
      next unless $part =~ /\S/;
    TRY: while (1) {
	$self->replace(\$part)
	  and next TRY;
	$self->replace_char(\$part)
	  and next TRY;
	$part =~ s#pre\[([^\]\[]+)\]#<pre>$1</pre>#ig
	  and next TRY;
	$part =~ s#h([1-6])\[([^\[\]\|]+)\|([^\[\]]+)\](?:\r?\n)?#
	  $self->_fix_spanned(qq/\n\n<h$1 class="$2">/, "</h$1>\n\n", $3)#ieg
	  and next TRY;
	$part =~ s#\n*h([1-6])\[\|([^\[\]]+)\]\n*#
	  $self->_fix_spanned("\n\n<h$1>", "</h$1>\n\n", $2)#ieg
	  and next TRY;
	$part =~ s#\n*h([1-6])\[([^\[\]]+)\]\n*#
	  $self->_fix_spanned("\n\n<h$1>", "</h$1>\n\n", $2)#ieg
	  and next TRY;
	$part =~ s#align\[([^|\]\[]+)\|([^\]\[]+)\]#<div align="$1">$2</div>#ig
	  and next TRY;
	$part =~ s#hr\[([^|\]\[]*)\|([^\]\[]*)\]#_make_hr($1, $2)#ieg
	  and next TRY;
	$part =~ s#hr\[([^|\]\[]*)\]#_make_hr($1, '')#ieg
	  and next TRY;
	$part =~ s#table\[([^\n\[\]]*)\n([^\[\]]+)\n\s*\]#_make_table($1, $2)#ieg
	  and next TRY;
	$part =~ s#table\[([^\]\[]+)\|([^\]\[|]+)\]#_make_table($1, "|$2")#ieg
	  and next TRY;
	#print STDERR "step: ",unpack("H*", $part),"\n$part\n";
	$part =~ s#(?:^|\n+|\G)((?: *(?:\*\*|\#\#|\%\%)[^\n]+(?:\n|$)\n?[^\S\n]*)+)\n?#"\n\n"._format_lists($1)."\n\n"#eg
	  and next TRY;
	$part =~ s#indent\[([^\]\[]+)\]#<ul>$1</ul>#ig
	  and next TRY;
	$part =~ s#center\[([^\]\[]+)\]#<center>$1</center>#ig
	  and next TRY;
	$part =~ s#hrcolor\[([^|\]\[]+)\|([^\]\[]+)\|([^\]\[]+)\]#<table width="$1" height="$2" border="0" bgcolor="$3" cellpadding="0" cellspacing="0"><tr><td><img src="/images/trans_pixel.gif" width="1" height="1" alt="" /></td></tr></table>#ig
	  and next TRY;
	$part =~ s#image\[([^\]\[]+)\]# $self->image($1) #ige
	    and next TRY;
	$part =~ s#class\[([^\]\[\|]+)\|([^\]\[]+)\]#
	  $self->_fix_spanned(qq/<span class="$1">/, "</span>", $2)#eig
	  and next TRY;
	$part =~ s#style\[([^\]\[\|]+)\|([^\]\[]+)\]#
	  $self->_fix_spanned(qq/<span style="$1">/, "</span>", $2)#eig
	  and next TRY;
	$part =~ s#(div|address|blockquote)\[\n*([^\[\]\|]+)\|\n*([^\[\]]+?)\n*\]#\n\n<$1 class="$2">$3</$1>\n\n#ig
	  and next TRY;
	$part =~ s#(div|address|blockquote)\[\n*\|([^\[\]]+?)\n*]#\n\n<$1>$2</$1>\n\n#ig
	  and next TRY;
	$part =~ s#(div|address|blockquote)\[\n*([^\[\]]+?)\n*]#\n\n<$1>$2</$1>\n\n#ig
	  and next TRY;
	last;
      }
      $part =~ s/^\s+|\s+\z//g; # avoid spurious leading/trailing <p>
      $part =~ s!(\n([ \r]*\n)*)!$1 eq "\n" ? "<br />\n" : "</p>\n<p>"!eg;
      $part = "<p>$part</p>";
      1 while $part =~ s/<p>(<div(?: [^>]*)?>)/$1<p>/g;
      1 while $part =~ s!</div></p>!</p></div>!g;
      1 while $part =~ s/<p>(<blockquote>)/$1<p>/g;
      1 while $part =~ s/<p>(<blockquote [^>]*>)/$1<p>/g;
      1 while $part =~ s!</blockquote></p>!</p></blockquote>!g;
      1 while $part =~ s/<p>(<address>)/$1<p>/g;
      1 while $part =~ s/<p>(<address [^>]*>)/$1<p>/g;
      1 while $part =~ s!</address></p>!</p></address>!g;
      $part =~ s!<p>(<hr[^>]*>)</p>!$1!g;
      $part =~ s!<p>(<(?:table|ol|ul|center|h[1-6])[^>]*>)!$1!g;
      $part =~ s!(</(?:table|ol|ul|center|h[1-6])>)</p>!$1!g;
      # attempts to convert class[name|paragraph] into <p class="name">...
      # tried to use a negative lookahead but it wouldn't work
      $part =~ s#(<p><span class="([^"<>]+)">(.*?)</span></p>)#
        my ($one, $two, $three)= ($1, $2, $3); 
        $3 =~ /<span/ ? $one : qq!<p class="$two">$three</p>!#ge;
      $part =~ s#(<p><span style="([^"<>]+)">(.*?)</span></p>)#
        my ($one, $two, $three)= ($1, $2, $3); 
        $3 =~ /<span/ ? $one : qq!<p style="$two">$three</p>!#ge;
      if (my $p_class = $self->tag_class('p')) {
	$part =~ s!(<p(?: style="[^"<>]+")?)>!$1 class="$p_class">!g;
      }
      #$part =~ s!\n!<br />!g;
      $out .= $part;
    }
  }
  
  return $out;
}

sub remove_format {
  my ($self, $body) = @_;

  defined $body 
    or confess "undef body supplied to remove_format";

  if ($body =~ /^<html>/i) {
    return _strip_html(substr($body, 6));
  }

  my $out = '';
  for my $part (split /((?:html\[(?:[^\[\]]*(?:(?:\[[^\[\]]*\])[^\[\]]*)*)\])
			|embed\[(?:[^,\[\]]*)(?:,(?:[^,\[\]]*)){0,2}\]
                        |pre\[(?:[^\[\]]*(?:(?:\[[^\[\]]*\])[^\[\]]*)*)\])/ix, $body) {
    #print STDERR "Part is $part\n";
    if ($part =~ /^html\[([^\[\]]*(?:(?:\[[^\[\]]*\])[^\[\]]*)*)\]$/i) {
      $out .= _strip_html($1);
    }
    elsif ($part =~ /^embed\[([^,\[\]]*),([^,\[\]]*)\]$/i) {
      $out .= ""; # what would you do here?
    }
    elsif ($part =~ /^embed\[([^,\[\]]*)\]$/i) {
      $out .= "";
    }
    elsif ($part =~ /^pre\[([^\[\]]*(?:(?:\[[^\[\]]*\])[^\[\]]*)*)\]$/i) {
      my $work = $1;
      $out .= $self->remove_format($work);
    }
    else {
    TRY: while (1) {
	$self->remove(\$part)
	  and next TRY;
	$part =~ s#(?:acronym|abbr|dfn)\[([^|\]\[]+)\|([^\]\[]+)\|([^\]\[]+)\]#$3#ig
	  and next TRY;
	$part =~ s#(?:acronym|abbr|dfn|bdo)\[([^|\]\[]+)\|([^\]\[]+)\]#$2#ig
	  and next TRY;
	$part =~ s#(?:acronym|abbr|dfn|bdo)\[(\|[^|\]\[]+)\]#$1#ig
	  and next TRY;
	$part =~ s#(?:acronym|abbr|dfn)\[([^|\]\[]+)\]#$1#ig
	  and next TRY;
	$part =~ s#(?:strong|em|samp|code|var|sub|sup|kbd|q|address|blockquote|b|i|tt)\[([^|\]\[]+)\|([^\]\[]+)\]#$2#ig
	  and next TRY;
	$part =~ s#(?:strong|em|samp|code|var|sub|sup|kbd|q|address|blockquote|b|i|tt)\[\|([^\]\[]+)\]#$1#ig
	  and next TRY;
	$part =~ s#(?:strong|em|samp|code|var|sub|sup|kbd|q|address|blockquote|b|i|tt)\[([^\]\[]+)\]#$1#ig
	  and next TRY;
	$part =~ s#div\[([^\[\]\|]+)\|([^\[\]]+)\](?:\r?\n)?#$2#ig
	  and next TRY;
	$part =~ s#h([1-6])\[([^\[\]\|]+)\|([^\[\]]+)\](?:\r?\n)?#$3#ig
	  and next TRY;
	$part =~ s#h([1-6])\[\|([^\[\]]+)\](?:\r?\n)?#$2#ig
	  and next TRY;
	$part =~ s#h([1-6])\[([^\[\]]+)\](?:\r?\n)?#$2#ig
	  and next TRY;
	$part =~ s#poplink\[([^|\]\[]+)\|([^\]\[]+)\]#$2#ig
	  and next TRY;
	$part =~ s#poplink\[([^|\]\[]+)\]#$1#ig
	  and next TRY;
	$part =~ s#link\[([^|\]\[]+)\|([^\]\[]+)\]#$2#ig
	  and next TRY;
	$part =~ s#link\[([^|\]\[]+)\]#$1#ig
	  and next TRY;
	$part =~ s#align\[([^|\]\[]+)\|([^\]\[]+)\]#$2#ig
	  and next TRY;
	$part =~ s#font\[([^|\]\[]+)\|([^\]\[]+)\]#$2#ig
	  and next TRY;
	$part =~ s#hr\[([^|\]\[]*)\|([^\]\[]*)\]##ig
	  and next TRY;
	$part =~ s#hr\[([^|\]\[]*)\]##ig
	  and next TRY;
	$part =~ s#anchor\[([^|\]\[]*)\]##ig
	  and next TRY;
	$part =~ s#table\[([^\n\[\]]*)\n([^\[\]]+)\n\s*\]#_cleanup_table($1, $2)#ieg
	  and next TRY;
	$part =~ s#table\[([^\]\[]+)\|([^\]\[|]+)\]#_cleanup_table($1, "|$2")#ieg
	  and next TRY;
	$part =~ s#\*\*([^\n]+)#$1#g
	  and next TRY;
	$part =~ s!##([^\n]+)!$1!g
	  and next TRY;
	$part =~ s!%%([^\n]+)!$1!g
	  and next TRY;
	$part =~ s#fontcolor\[([^|\]\[]+)\|([^\]\[]+)\|([^\]\[]+)\]#$3#ig
	  and next TRY;
	$part =~ s#(?:indent|center)\[([^\]\[]*)\]#$1#ig
	  and next TRY;
	$part =~ s#hrcolor\[([^|\]\[]+)\|([^\]\[]+)\|([^\]\[]+)\]##ig
	  and next TRY;
	$part =~ s#image\[([^\]\[]+)\]##ig
	  and next TRY;
	$part =~ s#class\[([^\]\[\|]+)\|([^\]\[]+)\]#$2#ig
	  and next TRY;
	$part =~ s#style\[([^\]\[\|]+)\|([^\]\[]+)\]#$2#ig
	  and next TRY;
	$part =~ s!(?<=\W)\[([^\]\[]+)\]!\x01$1\x02!g
          and next TRY;
	
	last TRY;
      }
      $part =~ tr/\x01\x02/[]/; # put back the bare []
      $out .= $part;
    }
  } 

  return $out;
}

sub remove {
  0;
}

# removes any html tags from the supplied text
sub _strip_html {
  my ($text) = @_;

  my $out = '';
  require HTML::Parser;
  
  # this may need to detect and skip <script></script> and stylesheets
  my $ignore_text = 0; # non-zero in a <script></script> or <style></style>
  my $start_h = 
    sub {
      ++$ignore_text if $_[0] eq 'script' or $_[0] eq 'style';
	if ($_[0] eq 'img' && $_[1]{alt} && !$ignore_text) {
	  $out .= $_[1]{alt};
	}
    };
  my $end_h = 
    sub {
      --$ignore_text if $_[0] eq 'script' or $_[0] eq 'style';
    };
    my $text_h = 
      sub { 
	$out .= $_[0] unless $ignore_text
      };
  my $p = HTML::Parser->new( text_h  => [ $text_h,  "dtext" ],
			     start_h => [ $start_h, "tagname, attr" ],
			     end_h   => [ $end_h,   "tagname" ]);
  $p->parse($text);
  $p->eof();
  
  $text = $out;

  return $text;
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

sub escape {
  my ($self, $html) = @_;

  if ($self->{conservative_escape}) {
    return escape_html($html, '<>&"');
  }
  else {
    return escape_html($html);
  }
}

# for subclasses to override
sub tag_class {
  return;
}

1;
