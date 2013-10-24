#!perl -w
use strict;
use Test::More tests => 137;

sub format_test($$$;$);
sub noformat_test($$$;$);

my $gotmodule = require_ok('DevHelp::Formatter');

++$|;

SKIP: {
  skip "couldn't load module", 63 unless $gotmodule;
  format_test 'acronym[hello]', '<p><acronym>hello</acronym></p>', 'acronym';
  format_test 'acronym[|hello]', '<p><acronym>hello</acronym></p>', 'acronym with empty title';
  format_test 'acronym[foo|hello]', '<p><acronym title="foo">hello</acronym></p>', 'acronym with title';
  format_test 'acronym[foo|bar|hello]', '<p><acronym class="bar" title="foo">hello</acronym></p>', 'acronym with class and title';
  format_test 'bdo[ltr|hello]', '<p><bdo dir="ltr">hello</bdo></p>', 'bdo with dir';
  format_test 'code[hello]', '<p><code>hello</code></p>', 'code';
  format_test 'code[|hello]', '<p><code>hello</code></p>', 'code empty class';
  format_test 'code[foo|hello]', '<p><code class="foo">hello</code></p>', 'code with class';
  format_test 'code[var[x]="1"]', '<p><code><var>x</var>=&quot;1&quot;</code></p>', 'code with var';
  format_test 'cite[hello]', '<p><cite>hello</cite></p>', 'cite';
  format_test 'cite[|hello]', '<p><cite>hello</cite></p>', 'cite with empty title';
  format_test 'cite[foo|hello]', '<p><cite title="foo">hello</cite></p>', 'cite with title';
  format_test 'cite[foo|bar|hello]', '<p><cite class="bar" title="foo">hello</cite></p>', 'cite with class and title';
  format_test 'small[hello]', '<p><small>hello</small></p>', 'small';
  format_test 'small[|hello]', '<p><small>hello</small></p>', 'small empty class';
  format_test 'small[foo|hello]', '<p><small class="foo">hello</small></p>', 'small with class';
  format_test 'large[hello]', '<p><large>hello</large></p>', 'large';
  format_test 'large[|hello]', '<p><large>hello</large></p>', 'large empty class';
  format_test 'large[foo|hello]', '<p><large class="foo">hello</large></p>', 'large with class';
  format_test 'mark[hello]', '<p><mark>hello</mark></p>', 'mark';
  format_test 'mark[|hello]', '<p><mark>hello</mark></p>', 'mark empty class';
  format_test 'mark[foo|hello]', '<p><mark class="foo">hello</mark></p>', 'mark with class';
  format_test 'link[foo|hello]', '<p><a href="foo">hello</a></p>', 'anchor';
  format_test 'poplink[foo|hello]', '<p><a href="foo" target="_blank">hello</a></p>', 'anchor with popup';
  format_test <<IN, <<OUT, 'blockquote', 'both';
blockquote[hello]

blockquote[

hello]
IN
<blockquote>hello</blockquote>
<blockquote>
<p>hello</p>
</blockquote>
OUT
  format_test <<IN, <<OUT, 'blockquote with empty class', 'both';
blockquote[|hello]

blockquote[|

hello

]
IN
<blockquote>hello</blockquote>
<blockquote>
<p>hello</p>
</blockquote>
OUT
  format_test <<IN, <<OUT, 'blockquote with class', 'both';
blockquote[foo|hello]

blockquote[foo|hello
world]

blockquote[foo|
hello
world]
IN
<blockquote class="foo">hello</blockquote>
<blockquote class="foo">hello<br />
world</blockquote>
<blockquote class="foo">
<p>hello<br />
world</p>
</blockquote>
OUT
  format_test <<IN, <<OUT, 'article', 'both';
article[hello]

article[

hello]
IN
<article>hello</article>
<article>
<p>hello</p>
</article>
OUT
  format_test <<IN, <<OUT, 'article with empty class', 'both';
article[|hello]

article[|

hello

]
IN
<article>hello</article>
<article>
<p>hello</p>
</article>
OUT
  format_test <<IN, <<OUT, 'article with id and class', 'both';
article[#id foo|hello]

article[#id foo|

hello]
IN
<article id="id" class="foo">hello</article>
<article id="id" class="foo">
<p>hello</p>
</article>
OUT
  format_test <<IN, <<OUT, 'section', 'both';
section[
hello
]
IN
<section>
<p>hello</p>
</section>
OUT
  format_test <<IN, <<OUT, 'section with empty class', 'both';
section[|
hello]
IN
<section>
<p>hello</p>
</section>
OUT
  format_test <<IN, <<OUT, 'section with id and class', 'both';
section[#id foo|hello

]
IN
<section id="id" class="foo">
<p>hello</p>
</section>
OUT
  format_test <<IN, <<OUT, 'header', 'both';
header[

hello]
IN
<header>
<p>hello</p>
</header>
OUT
  format_test <<IN, <<OUT, 'header with empty class', 'both';
header[|hello

]
IN
<header>
<p>hello</p>
</header>
OUT
  format_test <<IN, <<OUT, 'header with id and class', 'both';
header[#id foo|
hello
]
IN
<header id="id" class="foo">
<p>hello</p>
</header>
OUT
  format_test <<IN, <<OUT, 'footer', 'both';
footer[hello
world]
IN
<footer>hello<br />
world</footer>
OUT
  format_test <<IN, <<OUT, 'footer with empty class', 'both';
footer[|

hello

]
IN
<footer>
<p>hello</p>
</footer>
OUT
  format_test <<IN, <<OUT, 'footer with id and class', 'both';
footer[#id foo|hello

]
IN
<footer id="id" class="foo">
<p>hello</p>
</footer>
OUT
  format_test <<IN, <<OUT, 'aside', 'both';
aside[hello]
IN
<aside>hello</aside>
OUT
  format_test <<IN, <<OUT, 'aside with empty class', 'both';
aside[|hello]
IN
<aside>hello</aside>
OUT
  format_test <<IN, <<OUT, 'aside with id and class', 'both';
aside[#id foo|hello]
IN
<aside id="id" class="foo">hello</aside>
OUT
  format_test <<IN, <<OUT, 'nav', 'both';
nav[hello]
IN
<nav>hello</nav>
OUT
  format_test <<IN, <<OUT, 'nav with empty class', 'both';
nav[|

hello

]
IN
<nav>
<p>hello</p>
</nav>
OUT
  format_test <<IN, <<OUT, 'nav with id and class', 'both';
nav[#id foo|hello]
IN
<nav id="id" class="foo">hello</nav>
OUT
  format_test <<IN, <<OUT, 'figure', 'both';
figure[hello]
IN
<figure>hello</figure>
OUT
  format_test <<IN, <<OUT, 'figure with empty class', 'both';
figure[|hello]
IN
<figure>hello</figure>
OUT
  format_test <<IN, <<OUT, 'figure with id and class', 'both';
figure[#id foo|hello]
IN
<figure id="id" class="foo">hello</figure>
OUT
  format_test <<IN, <<OUT, 'figcaption', 'both';
figcaption[hello]
IN
<figcaption>hello</figcaption>
OUT
  format_test <<IN, <<OUT, 'figcaption with empty class', 'both';
figcaption[|hello]
IN
<figcaption>hello</figcaption>
OUT
  format_test <<IN, <<OUT, 'figcaption with id and class', 'both';
figcaption[#id foo|hello]
IN
<figcaption id="id" class="foo">hello</figcaption>
OUT
  format_test <<IN, <<OUT, 'strong over paras', 'both';
strong[foo|hello

foo]
IN
<p><strong class="foo">hello</strong></p>
<p><strong class="foo">foo</strong></p>
OUT
  format_test <<IN, <<OUT, 'blockquote list h1 var', 'both';
blockquote[
** one
** two
h1[quux]var[hello
there]

foo]
IN
<blockquote>
<ul><li>one</li><li>two</li></ul>
<h1>quux</h1>
<p><var>hello<br />
there</var></p>
<p>foo</p>
</blockquote>
OUT
  format_test <<IN, <<OUT, 'address class h1 abbr over paras', 'both';
address[foo|h1[bar

quux]abbr[my abbr|hello]

class[foo|b[bold|E=MCsup[2]]]

foo]
IN
<address class="foo">
<h1>bar</h1>
<h1>quux</h1>
<p><abbr title="my abbr">hello</abbr></p>
<p class="foo"><b class="bold">E=MC<sup>2</sup></b></p>
<p>foo</p>
</address>
OUT
  format_test <<IN, <<OUT, 'div blockquote h1 class over paras', 'both';
div[quux|blockquote[foo|h1[bar]
b[hello]
class[foo|b[bold|E=MCsup[2

kbd[xxx|super]]]]

foo]]
IN
<div class="quux">
<blockquote class="foo">
<h1>bar</h1>
<p><b>hello</b><br />
<span class="foo"><b class="bold">E=MC<sup>2</sup></b></span></p>
<p class="foo"><b class="bold"><sup><kbd class="xxx">super</kbd></sup></b></p>
<p>foo</p>
</blockquote>
</div>
OUT
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
link[http://foo/|bar

quux]
IN
<a href="http://foo/"><p>bar</p>
<p>quux</p></a>
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
  format_test <<IN, <<OUT, 'align', 'both';
align[left|some text]
IN
<div align="left">
<p>some text</p>
</div>
OUT
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

  format_test <<IN, <<OUT, 'spaces between', 'both';
** joe
 
** bob

** jane
IN
<ul><li><p>joe</p></li><li><p>bob</p></li><li>jane</li></ul>
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
<div class="someclass">
<h1>foo</h1>
<p>bar</p>
<h2>quux</h2>
</div>
EOS

  format_test "h1[#foo|test]", q!<h1 id="foo">test</h1>!, 'h1#id';
  format_test "h1[#foo bar|test]", q!<h1 id="foo" class="bar">test</h1>!, 'h1#id class';
  format_test "h1[#foo bar quux|test]", q!<h1 id="foo" class="bar quux">test</h1>!, 'h1#id class class';
  format_test "h1[text-align: center;|test]", q!<h1 style="text-align: center;">test</h1>!, 'h1 styled';
  format_test "h1[#foo text-align: center;|test]", q!<h1 id="foo" style="text-align: center;">test</h1>!, 'h1 styled, id';

  format_test "div[text-align: center;|test\n\ntest2]", <<EOS, 'div styled', 'out';
<div style="text-align: center;">
<p>test</p>
<p>test2</p>
</div>
EOS

  format_test "div[#foo|test\n\ntest2]", <<EOS, 'div #id', 'out';
<div id="foo">
<p>test</p>
<p>test2</p>
</div>
EOS

  format_test "abc comment[foo] def", "<p>abc  def</p>", "comment";
  format_test  <<IN, <<OUT, 'link over paras following an hr', 'both';
hr[100%]

link[#foo|hello

world]

link[#foo|
hello

world]
IN
<hr width="100%" />
<a href="#foo"><p>hello</p>
<p>world</p>
</a>
<a href="#foo"><p>hello</p>
<p>world</p>
</a>
OUT

  # remove_format() tests
  noformat_test 'image[foo]', '', 'image';
  noformat_test 'code[something [bar]]', 'something [bar]', 'nested []';

  noformat_test "abc comment[foo] def", "abc  def", "comment";

  noformat_test 'class[foo|image[bar]]', '', 'class with image content';
  noformat_test 'abbr[image[bar]]', '', 'abbr[] with image content';
  noformat_test 'abbr[foo|image[bar]]', '', 'abbr[x|x] with image content';
  noformat_test 'abbr[|image[bar]]', '', 'abbr[|x] with image content';
  noformat_test 'strong[image[bar]]', '', 'strong[x] with image content';
  noformat_test 'strong[|image[bar]]', '', 'strong[|x] with image content';
  noformat_test 'strong[foo|image[bar]]', '', 'strong[x|x] with image content';

  noformat_test 'div[foo|image[bar]]', '', 'div[x|x] with image content';
  noformat_test 'comment[image[bar]]', '', 'comment[image[xx]] with image content';
  noformat_test 'h1[foo|image[bar]]', '', 'h1[x|x] with image content';
  noformat_test 'h1[|image[bar]]', '', 'h1[|x] with image content';
  noformat_test 'h1[image[bar]]', '', 'h1[x] with image content';
  
  noformat_test 'poplink[xxx|image[bar]]', '', 'poplink[x|x] with image content';
  noformat_test 'poplink[image[bar]]', '', 'poplink[x] with image content';
  noformat_test 'link[xxx|image[bar]]', '', 'link[x|x] with image content';
  noformat_test 'link[image[bar]]', '', 'link[x] with image content';
  noformat_test 'align[xxx|image[bar]]', '', 'align[x|x] with image content';
  noformat_test 'font[xxx|image[bar]]', '', 'font[x|x] with image content';
  noformat_test 'hr[xxx|image[bar]]', '', 'hr[x|x] with image content';
  noformat_test 'anchor[image[bar]]', '', 'anchor[x] with image content';
  noformat_test '**image[bar]', '', '** list with image content';
  noformat_test '%%image[bar]', '', '%% list with image content';
  noformat_test '##image[bar]', '', '## list with image content';
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

sub noformat_test($$$;$) {
  my ($in, $out, $desc, $stripnl) = @_;

  $stripnl ||= 'none';
  $in =~ s/\n$// if $stripnl eq 'in' || $stripnl eq 'both';
  $out =~ s/\n$// if $stripnl eq 'out' || $stripnl eq 'both';

  my $formatter = DevHelp::Formatter->new;

  my $result = $formatter->remove_format($in);

  is($result, $out, $desc);
}
