#!perl -w
use strict;
use Test::More tests => 37;

sub format_test($$$;$);

my $gotmodule = require_ok('DevHelp::Formatter');

SKIP: {
  skip "couldn't load module", 35 unless $gotmodule;

  format_test <<IN, <<OUT, 'bold', 'both';
b[hello]
IN
<b>hello</b>
OUT
  format_test 'i[hello]', '<i>hello</i>', 'italic';
  format_test 'b[i[hello]]', '<b><i>hello</i></b>', 'bold/italic';
  format_test <<IN, <<OUT, 'bold over lines', 'both';
b[hello
foo]
IN
<b>hello<br />
foo</b>
OUT
  format_test <<IN, <<OUT, 'bold over paras', 'both';
b[hello

foo]
IN
<b>hello</b></p>
<p><b>foo</b>
OUT
  format_test <<IN, <<OUT, 'combo over paras', 'both';
i[b[hello

foo

bar]]
IN
<i><b>hello</b></i></p>
<p><i><b>foo</b></i></p>
<p><i><b>bar</b></i>
OUT
  format_test <<IN, <<OUT, 'link', 'both';
link[http://foo/|bar]
IN
<a href="http://foo/">bar</a>
OUT
  format_test 'tt[hello]', '<tt>hello</tt>', 'tt';
  format_test 'font[-1|text]', '<font size="-1">text</font>', 'fontsize';
  format_test 'fontcolor[-1|black|text]', '<font size="-1" color="black">text</font>', 'fontsizecolor';
  format_test 'anchor[somename]', '<a name="somename"></a>', 'anchor';
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
  format_test 'align[left|some text]', '<div align="left">some text</div>', 'align';
  format_test 'hr[]', '<hr />', 'hr0';
  format_test 'hr[80%]', '<hr width="80%" />', 'hr1';
  format_test 'hr[80%|10]', '<hr width="80%" height="10" />', 'hr2';
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
<ol><li>one<br /><br /></li><li>two</li></ol>
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
<ul><li>one<br /><br /></li><li>two</li></ul>
OUT

  format_test 'indent[text]', '<ul>text</ul>', 'indent';
  format_test 'center[text]', '<center>text</center>', 'center';
  format_test 'hrcolor[80|10|#FF0000]', <<OUT, 'hrcolor', 'out';
<table width="80" height="10" border="0" bgcolor="#FF0000" cellpadding="0" cellspacing="0"><tr><td><img src="/images/trans_pixel.gif" width="1" height="1" alt="" /></td></tr></table>
OUT
  format_test 'image[foo]', '', 'image';

  format_test 'class[xxx|yyy]', '<span class="xxx">yyy</span>', 'class';
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
