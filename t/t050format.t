#!perl -w
use strict;
use Test::More tests => 46;

sub format_test($$$;$);

my $gotmodule = require_ok('DevHelp::Formatter');

SKIP: {
  skip "couldn't load module", 41 unless $gotmodule;

  format_test <<IN, <<OUT, 'bold', 'both';
b[hello]
IN
<p><b>hello</b></p>
OUT
  format_test 'i[hello]', '<p><i>hello</i></p>', 'italic';
  format_test 'b[i[hello]]', '<p><b><i>hello</i></b></p>', 'bold/italic';
  format_test <<IN, <<OUT, 'bold over lines', 'both';
b[hello
foo]
IN
<p><b>hello<br />
foo</b></p>
OUT
  format_test <<IN, <<OUT, 'bold over paras', 'both';
b[hello

foo]
IN
<p><b>hello</b></p>
<p><b>foo</b></p>
OUT
  format_test <<IN, <<OUT, 'combo over paras', 'both';
i[b[hello

foo

bar]]
IN
<p><i><b>hello</b></i></p>
<p><i><b>foo</b></i></p>
<p><i><b>bar</b></i></p>
OUT
  format_test <<IN, <<OUT, 'link', 'both';
link[http://foo/|bar]
IN
<p><a href="http://foo/">bar</a></p>
OUT
  format_test 'tt[hello]', '<p><tt>hello</tt></p>', 'tt';
  format_test 'font[-1|text]', '<p><font size="-1">text</font></p>', 'fontsize';
  format_test 'fontcolor[-1|black|text]', '<p><font size="-1" color="black">text</font></p>', 'fontsizecolor';
  format_test 'anchor[somename]', '<p><a name="somename"></a></p>', 'anchor';
  format_test <<IN, <<OUT, 'pre', 'both';


pre[hello there
Joe]
IN
<pre>hello there
Joe</pre>
OUT
  format_test <<IN, <<OUT, 'pre with bold', 'both';
pre[b[hello there

Joe]]
IN
<pre><b>hello there</b>

<b>Joe</b></pre>
OUT
  format_test <<IN, <<OUT, 'html', 'both';
html[<object foo="bar" />]
IN
<object foo="bar" />
OUT

  format_test 'embed[foo]', '', 'embed1';
  format_test 'embed[foo,bar]', '', 'embed2';
  format_test 'embed[foo,bar,quux]', '', 'embed3';
  format_test 'h1[|text]', '<h1>text</h1>', 'h1';
  format_test 'h1[someclass|text]', '<h1 class="someclass">text</h1>', 'h1class';
  format_test 'h6[|te>xt]', '<h6>te&gt;xt</h6>', 'h6';
  format_test 'h1[|foo]h2[|bar]', "<h1>foo</h1>\n<h2>bar</h2>", 'h1h2';
  format_test 'h1[|foo]texth2[|bar]', 
    "<h1>foo</h1>\n<p>text</p>\n<h2>bar</h2>", 'h1texth2';
  format_test 'align[left|some text]', '<div align="left"><p>some text</p></div>', 'align';
  format_test 'hr[]', '<hr />', 'hr0';
  format_test 'hr[80%]', '<hr width="80%" />', 'hr1';
  format_test 'hr[80%|10]', '<hr width="80%" size="10" />', 'hr2';
  format_test <<IN, <<OUT, 'table1', 'both';
table[80%
bgcolor="black"|quux|blarg
|hello|there
]
IN
<table width="80%"><tr bgcolor="black"><td>quux</td><td>blarg</td></tr><tr><td>hello</td><td>there</td></tr></table>
OUT
  format_test <<IN, <<OUT, 'table2', 'both';
table[80%|#808080|2|2|Arial
bgcolor="black"|quux|blarg
|hello|there
]
IN
<table width="80%" bgcolor="#808080" cellpadding="2"><tr bgcolor="black"><td><font size="2" face="Arial">quux</font></td><td><font size="2" face="Arial">blarg</font></td></tr><tr><td><font size="2" face="Arial">hello</font></td><td><font size="2" face="Arial">there</font></td></tr></table>
OUT
  format_test <<IN, <<OUT, 'table3', 'both';
table[80%|foo]
IN
<table width="80%"><tr><td>foo</td></tr></table>
OUT
  format_test <<IN, <<OUT, 'ol1', 'both';
## one
## two
IN
<ol><li>one</li><li>two</li></ol>
OUT
  format_test <<IN, <<OUT, 'ol2', 'both';
## one

## two
IN
<ol><li><p>one</p></li><li>two</li></ol>
OUT
  format_test <<IN, <<OUT, 'ol1 alpha', 'both';
%% one
%% two
IN
<ol type="a"><li>one</li><li>two</li></ol>
OUT
  format_test <<IN, <<OUT, 'ol2 alpha', 'both';
%% one

%% two
IN
<ol type="a"><li><p>one</p></li><li>two</li></ol>
OUT
  format_test <<IN, <<OUT, 'ul1', 'both';
** one
** two
IN
<ul><li>one</li><li>two</li></ul>
OUT
  format_test <<IN, <<OUT, 'ul2', 'both';
** one

** two
IN
<ul><li><p>one</p></li><li>two</li></ul>
OUT

  format_test <<IN, <<OUT, 'ul indented', 'both';
  ** one
**two
IN
<ul><li>one</li><li>two</li></ul>
OUT

  format_test <<IN, <<OUT, "don't ul at end of line", 'both';
this shouldn't be a bullet ** some text

** this should be a bullet
** so should this
IN
<p>this shouldn't be a bullet ** some text</p>
<ul><li>this should be a bullet</li><li>so should this</li></ul>
OUT

  format_test <<IN, <<OUT, 'mixed', 'both';
** joe
** bob
## one
## two
IN
<ul><li>joe</li><li>bob</li></ul><ol><li>one</li><li>two</li></ol>
OUT

  format_test 'indent[text]', '<ul>text</ul>', 'indent';
  format_test 'center[text]', '<center>text</center>', 'center';
  format_test 'hrcolor[80|10|#FF0000]', <<OUT, 'hrcolor', 'out';
<table width="80" height="10" border="0" bgcolor="#FF0000" cellpadding="0" cellspacing="0"><tr><td><img src="/images/trans_pixel.gif" width="1" height="1" alt="" /></td></tr></table>
OUT
  format_test 'image[foo]', '<p></p>', 'image';

  format_test 'class[xxx|yyy]', '<p class="xxx">yyy</p>', 'class';
  format_test "class[xxx|yy\n\nzz]", <<EOS, 'class2', 'out';
<p class="xxx">yy</p>
<p class="xxx">zz</p>
EOS
  format_test 'div[someclass|h1[|foo]barh2[|quux]]', <<EOS, 'divblock', 'out';
<div class="someclass"><h1>foo</h1>
<p>bar</p>
<h2>quux</h2></div>
EOS
}

sub format_test ($$$;$) {
  my ($in, $out, $desc, $stripnl) = @_;

  $stripnl ||= 'none';
  $in =~ s/\n$// if $stripnl eq 'in' || $stripnl eq 'both';
  $out =~ s/\n$// if $stripnl eq 'out' || $stripnl eq 'both';

  my $formatter = DevHelp::Formatter->new;

  my $result = $formatter->format($in);

  is($result, $out, $desc);
}
