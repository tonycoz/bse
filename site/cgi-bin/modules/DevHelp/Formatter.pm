package DevHelp::Formatter;
use strict;
use DevHelp::HTML;

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
  $tag .= qq! height="$height"! if length $height;
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
  my @points = split /(?:\r?\n)?\*\*\s*/, $text;
  shift @points if @points and $points[0] eq '';
  return '' unless @points;
  for my $point (@points) {
    $point =~ s!\n$!<br /><br />!;
  }
  return "<ul><li>".join("</li><li>", @points)."</li></ul>";
}

# make a OL
sub _format_ol {
  my ($text) = @_;
  $text =~ s/^\s+|\s+$//g;
  my @points = split /(?:\r?\n)?##\s*/, $text;
  shift @points if @points and $points[0] eq '';
  return '' unless @points;
  for my $point (@points) {
    $point =~ s!\n$!<br /><br />!;
  }
  return "<ol><li>".join("</li><li>", @points)."</li></ol>";
}

# raw html - this has some limitations
# the input text has already been escaped, so we need to unescape it
# too bad if you want [] in your html (but you can use entities)
sub _make_html {
  return unescape_html($_[0]);
}

sub _fix_spanned {
  my ($start, $end, $text) = @_;

  $text =~ s!(\n(?:[ \r]*\n)+)!$end$1$start!g;

  "$start$text$end";
}

sub replace_char {
  my ($self, $rpart) = @_;

  $$rpart =~ s#link\[([^|\]\[]+)\|([^\]\[]+)\]#<a href="$1">$2</a>#ig
    and return 1;
  $$rpart =~ s#b\[([^\]\[]+)\]#_fix_spanned("<b>", "</b>", $1)#egi
    and return 1;
  $$rpart =~ s#i\[([^\]\[]+)\]#_fix_spanned("<i>", "</i>", $1)#egi
    and return 1;
  $$rpart =~ s#tt\[([^\]\[]+)\]#_fix_spanned("<tt>", "</tt>", $1)#egi
    and return 1;
  $$rpart =~ s#font\[([^|\]\[]+)\|([^\]\[]+)\]#
    _fix_spanned(qq/<font size="$1">/, "</font>", $2)#egi
      and return 1;
  $$rpart =~ s#anchor\[([^|\]\[]*)\]#<a name="$1"></a>#ig
    and return 1;
  $$rpart =~ s#fontcolor\[([^|\]\[]+)\|([^\]\[]+)\|([^\]\[]+)\]#
    _fix_spanned(qq/<font size="$1" color="$2">/, "</font>", $3)#egi
      and return 1;
  
  return 0;
}

sub format {
  my ($self, $body) = @_;

  $body = escape_html($body);
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
    TRY: while (1) {
	$self->replace(\$part)
	  and next TRY;
	$self->replace_char(\$part)
	  and next TRY;
	$part =~ s#pre\[([^\]\[]+)\]#<pre>$1</pre>#ig
	  and next TRY;
	$part =~ s#h([1-6])\[\|([^\[\]]+)\](?:\r?\n)?#<h$1>$2</h$1>#ig
          and next TRY;
	$part =~ s#h([1-6])\[([^\[\]\|]+)\|([^\[\]]+)\](?:\r?\n)?#<h$1 class="$2">$3</h$1>#ig
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
	$part =~ s#\n{0,2}((?:\*\*[^\n]+(?:\n|$)\n?[^\S\n]*)+)\n?#_format_bullets($1)#eg
	  and next TRY;
	$part =~ s!\n{0,2}((?:##[^\n]+(?:\n|$)\n?[^\S\n]*)+)\n?!_format_ol($1)!eg
	  and next TRY;
	$part =~ s#indent\[([^\]\[]+)\]#<ul>$1</ul>#ig
	  and next TRY;
	$part =~ s#center\[([^\]\[]+)\]#<center>$1</center>#ig
	  and next TRY;
	$part =~ s#hrcolor\[([^|\]\[]+)\|([^\]\[]+)\|([^\]\[]+)\]#<table width="$1" height="$2" border="0" bgcolor="$3" cellpadding="0" cellspacing="0"><tr><td><img src="/images/trans_pixel.gif" width="1" height="1" alt="" /></td></tr></table>#ig
	  and next TRY;
	$part =~ s#image\[([^\]\[]+)\]# $self->image($1) #ige
	    and next TRY;
	last;
      }
      $part =~ s!(\n([ \r]*\n)*)!$1 eq "\n" ? "<br />\n" : "</p>\n<p>"!eg;
      #$part =~ s!\n!<br />!g;
      $out .= $part;
    }
  }
  
  return $out;
}

sub remove_format {
  my ($self, $body) = @_;

  if ($body =~ /^<html>/i) {
    return _strip_html(substr($body, 6));
  }

  my $out = '';
  for my $part (split /((?:html\[(?:[^\[\]]*(?:(?:\[[^\[\]]*\])[^\[\]]*)*)\])
			|embed\[(?:[^,\[\]]*)(?:,(?:[^,\[\]]*)){0,2}\])/ix, $body) {
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
    else {
    TRY: while (1) {
	$self->remove(\$part)
	  and next TRY;
	$part =~ s#link\[([^|\]\[]+)\|([^\]\[]+)\]#$2#ig
	  and next TRY;
	$part =~ s#([bi])\[([^\]\[]+)\]#$2#ig
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
	$part =~ s#fontcolor\[([^|\]\[]+)\|([^\]\[]+)\|([^\]\[]+)\]#$3#ig
	  and next TRY;
	$part =~ s#(?:indent|center)\[([^\]\[]*)\]#$1#ig
	  and next TRY;
	$part =~ s#hrcolor\[([^|\]\[]+)\|([^\]\[]+)\|([^\]\[]+)\]##ig
	  and next TRY;
	$part =~ s#image\[([^\]\[]+)\]##ig
	  and next TRY;
	
	last TRY;
      }
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

1;
