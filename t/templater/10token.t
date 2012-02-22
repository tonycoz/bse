#!perl -w
use strict;
use Test::More tests => 35;
use Squirrel::Template;
use Squirrel::Template::Constants qw(:token);

sub test_tokens($$$);

# test the interface
my $templater = Squirrel::Template->new();
my $t = Squirrel::Template::Tokenizer->new("content\n<:sometag foo:>", "<test>", $templater);

ok($t, "make a tokenizer");

my $peek = $t->peek;
my $token = $t->get;
is_deeply($peek, $token, "peek should be the same as following get");
is($t->peek_type, "tag", "tag type coming up next");
$t->unget($token);
is($t->peek_type, "content", "unget of content means type of next should be content");
$t->get;
is($t->peek_type, "tag", "consume, and next should be tag again");
$t->get;
is($t->peek_type, "eof", "consume, and next should be eof");
$t->get;
is($t->peek_type, "", "consume, and next type should be empty string");
is($t->peek, undef, "peek should be nothing");
is($t->get, undef, "get should be nothing");


# test the token stream

test_tokens("abc",
	    [
	     [ content => "abc", 1, '<string>' ],
	     [ eof => "", 1, "<string>" ]
	    ], "simple");
test_tokens("abc\n",
	    [
	     [ content => "abc\n", 1, '<string>' ],
	     [ eof => "", 2, "<string>" ]
	    ], "simple nl");
test_tokens("<:foo:>",
	    [
	     [ tag => "<:foo:>", 1, "<string>", "foo", "" ],
	     [ eof => "", 1, "<string>" ],
	    ], "simple tag");
test_tokens("<:foo\nsplit\nover lines:>",
	    [
	     [ tag => "<:foo\nsplit\nover lines:>", 1, "<string>", "foo", "split\nover lines" ],
	     [ eof => "", 3, "<string>" ],
	    ], "simple tag split over lines");
	    
test_tokens("<:ifFoo:>TRUE\n<:or:>FALSE\n<:eif\n:>\n",
	    [
	     [ if => "<:ifFoo:>", 1, "<string>", "Foo", "" ],
	     [ content => "TRUE\n", 1, "<string>" ],
	     [ or => "<:or:>", 2, "<string>", "" ],
	     [ content => "FALSE\n", 2, "<string>" ],
	     [ eif => "<:eif\n:>", 3, "<string>", "" ],
	     [ content => "\n", 4, "<string>" ],
	     [ eof => "", 5, "<string>" ],
	    ], "tight cond");

test_tokens("<:if Foo:>YES\n<:or Foo:>NO\n<:eif\nFoo:>\n",
	    [
	     [ if => "<:if Foo:>", 1, "<string>", "Foo", "" ],
	     [ content => "YES\n", 1, "<string>" ],
	     [ or => "<:or Foo:>", 2, "<string>", "Foo" ],
	     [ content => "NO\n", 2, "<string>" ],
	     [ eif => "<:eif\nFoo:>", 3, "<string>", "Foo" ],
	     [ content => "\n", 4, "<string>" ],
	     [ eof => "", 5, "<string>" ],
	    ], "loose cond");

test_tokens("<:ifFoo args:><:if Bar more args:>",
	    [
	     [ if => "<:ifFoo args:>", 1, "<string>", "Foo", "args" ],
	     [ if => "<:if Bar more args:>", 1, "<string>", "Bar", "more args" ],
	     [ eof => "", 1, "<string>" ],
	    ], "tight cond");

test_tokens("<:include notfoundfile:>",
	    [
	     [ error => "<:include notfoundfile:>", 1, "<string>",
	       "cannot find include notfoundfile in path" ],
	     [ eof => "", 1, "<string>" ],
	    ], "failed include");
test_tokens("<:include notfoundfile optional:>",
	    [
	     [ eof => "", 1, "<string>" ],
	    ], "failed optional include");
test_tokens("<:include notfoundfile optional:>abc",
	    [
	     [ content => "abc", 1, "<string>" ],
	     [ eof => "", 1, "<string>" ],
	    ], "failed optional include with following content");
test_tokens("<:include included.include:>",
	    [
	     [ content => "y", 1, "t/templates/included.include" ],
	     [ eof => "", 1, "<string>" ],
	    ], "successful include");
test_tokens("<:include included.recursive:>",
	    [
	     [ error => "<:include included.recursive:>", 1,
	       "t/templates/included.recursive", "Too many levels of includes" ],
	     [ eof => "", 1, "<string>" ],
	    ], "include loop");
test_tokens(<<EOS,
<:iterator begin foo test -:>
stuff here
<:iterator end foo:>
EOS
	    [
	     [ itbegin => "<:iterator begin foo test -:>\n", 1, "<string>",
	       "foo", "test" ],
	     [ content => "stuff here\n", 2, "<string>" ],
	     [ itend => "<:iterator end foo:>", 3, "<string>", "foo" ],
	     [ content => "\n", 3, "<string>" ],
	     [ eof => "", 4, "<string>" ],
	    ], "simple iterator");

test_tokens(<<EOS,
<:iterator begin foo test -:>
stuff here
<:iterator separator foo:>
more stuff
<:iterator end foo:>
EOS
	    [
	     [ itbegin => "<:iterator begin foo test -:>\n", 1, "<string>",
	       "foo", "test" ],
	     [ content => "stuff here\n", 2, "<string>" ],
	     [ itsep => "<:iterator separator foo:>", 3, "<string>", "foo" ],
	     [ content => "\nmore stuff\n", 3, "<string>" ],
	     [ itend => "<:iterator end foo:>", 5, "<string>", "foo" ],
	     [ content => "\n", 5, "<string>" ],
	     [ eof => "", 6, "<string>" ],
	    ], "iterator with sep");

test_tokens(<<EOS,
<:iterator begin foo:>
stuff here
<:iterator end foo:>
EOS
	    [
	     [ itbegin => "<:iterator begin foo:>", 1, "<string>", "foo", "" ],
	     [ content => "\nstuff here\n", 1, "<string>" ],
	     [ itend => "<:iterator end foo:>", 3, "<string>", "foo" ],
	     [ content => "\n", 3, "<string>" ],
	     [ eof => "", 4, "<string>" ],
	    ], "simple iterator, no args");

test_tokens(<<EOS,
<:with begin foo:>
stuff here
<:with end foo:>
EOS
	    [
	     [ withbegin => "<:with begin foo:>", 1, "<string>", "foo", "" ],
	     [ content => "\nstuff here\n", 1, "<string>" ],
	     [ withend => "<:with end foo:>", 3, "<string>", "foo" ],
	     [ content => "\n", 3, "<string>" ],
	     [ eof => "", 4, "<string>" ],
	    ], "simple with, no args");

test_tokens(<<EOS,
<:with begin foo blargh:>
EOS
	    [
	     [ withbegin => "<:with begin foo blargh:>", 1, "<string>", "foo", "blargh" ],
	     [ content => "\n", 1, "<string>" ],
	     [ eof => "", 2, "<string>" ],
	    ], "simple with, with args");

test_tokens(<<EOS,
<:switch:>
<:case Foo y -:>
<:case Bar x:>
<:case default:>
<:endswitch -:>
EOS
	    [
	     [ switch => "<:switch:>", 1, "<string>", "" ],
	     [ content => "\n", 1, "<string>" ],
	     [ case => "<:case Foo y -:>\n", 2, "<string>", "Foo", "y" ],
	     [ case => "<:case Bar x:>", 3, "<string>", "Bar", "x" ],
	     [ content => "\n", 3, "<string>" ],
	     [ case => "<:case default:>", 4, "<string>", "default", "" ],
	     [ content => "\n", 4, "<string>" ],
	     [ endswitch => "<:endswitch -:>\n", 5, "<string>", "" ],
	     [ eof => "", 6, "<string>" ],
	    ], "switch");

test_tokens(<<EOS,
<:wrap foo.tmpl a => 1, b => "2", c => [test]:>
<:wrap bar.tmpl :>
<:param a:>
EOS
	    [
	     [ wrap => '<:wrap foo.tmpl a => 1, b => "2", c => [test]:>', 1, "<string>",
	       "foo.tmpl", 'a => 1, b => "2", c => [test]' ],
	     [ content => "\n", 1, "<string>" ],
	     [ wrap => '<:wrap bar.tmpl :>', 2, "<string>", "bar.tmpl", '' ],
	     [ content => "\n", 2, "<string>" ],
	     [ tag => "<:param a:>", 3, "<string>", "param", "a" ],
	     [ content => "\n", 3, "<string>" ],
	     [ eof => "", 4, "<string>" ],
	    ], "top wrap");

test_tokens(<<EOS,
alpha <:wrap here:> beta
EOS
	    [
	     [ content => "alpha ", 1, "<string>" ],
	     [ wraphere => "<:wrap here:>", 1, "<string>" ],
	     [ content => " beta\n", 1, "<string>" ],
	     [ eof => "", 2, "<string>" ],
	    ], "wrap here");

test_tokens(<<EOS,
<: rubbish
EOS
	    [
	     [ error => "<: rubbish\n", 1, "<string>", "Unclosed tag 'rubbish'" ],
	     [ eof => "", 2, "<string>" ],
	    ], "incomplete tag with name");

test_tokens(<<EOS,
<:
EOS
	    [
	     [ error => "<:\n", 1, "<string>", "Unclosed tag '(no name found)'" ],
	     [ eof => "", 2, "<string>" ],
	    ], "incomplete tag without name");

test_tokens(<<EOS,
some content <:
EOS
	    [
	     [ content => "some content ", 1, "<string>" ],
	     [ error => "<:\n", 1, "<string>", "Unclosed tag '(no name found)'" ],
	     [ eof => "", 2, "<string>" ],
	    ], "incomplete tag without name, with some content before");

test_tokens(<<EOS,
<:iterator xbegin foo:>
EOS
	    [
	     [ error => "<:iterator xbegin foo:>", 1, "<string>", "Syntax error: incorrect use of 'iterator'" ],
	     [ content => "\n", 1, "<string>" ],
	     [ eof => "", 2, "<string>" ],
	    ], "syntax error - bad use of reserved word with bad syntax");

test_tokens(<<EOS,
<:*&:>
<:*&*&*&*&*&*&*&*&*&*&*&:>
EOS
	    [
	     [ error => "<:*&:>", 1, "<string>", "Syntax error: unknown tag start '*&'" ],
	     [ content => "\n", 1, "<string>" ],
	     [ error => "<:*&*&*&*&*&*&*&*&*&*&*&:>", 2, "<string>", "Syntax error: unknown tag start '*&*&*&*&*&*&*&*&*...'" ],
	     [ content => "\n", 2, "<string>" ],
	     [ eof => "", 3, "<string>" ],
	    ], "syntax error - unknown tag start");

test_tokens(<<EOS,
<:# some comment text:>
<:#
  multi-line
  comment
:>
EOS
	    [
	     [ comment => "<:# some comment text:>", 1, "<string>", "some comment text" ],
	     [ content => "\n", 1, "<string>" ],
	     [ comment => "<:#\n  multi-line\n  comment\n:>", 2, "<string>",
	       "multi-line\n  comment" ],
	     [ content => "\n", 5, "<string>" ],
	     [ eof => "", 6, "<string>" ],
	    ], "comment");

sub test_tokens($$$) {
  my ($text, $tokens, $name) = @_;

  my $tmpl = Squirrel::Template->new(template_dir=>'t/templates');
  my $tok = Squirrel::Template::Tokenizer->new($text, "<string>", $tmpl);

  my @rtokens;
  while (my $token = $tok->get) {
    push @rtokens, $token;
  }
  #use Data::Dumper;
  #diag(Dumper \@rtokens);
  my $result = 1;
  my $tb= Test::Builder->new;
  my $cmp_index = @rtokens < @$tokens ? $#rtokens : $#$tokens;
  CMP: for my $i (0 .. $cmp_index) {
    my $fe = _format_token($tokens->[$i]);
    my $ff = _format_token($rtokens[$i]);
    if ($fe ne $ff) {
      $result = $tb->ok(0, $name);
      diag(<<EOS);
Mismatch at index $i:
Expected: $fe
Found   : $ff
EOS
      last CMP;
    }
  }
  if ($result) {
    if (@rtokens < @$tokens) {
      $result = $tb->ok(0, $name);
      my $fe = _format_token($tokens->[$cmp_index+1]);
      diag(<<EOS)
Found shorter than expected:
Expected: $fe
Found   : no entry
EOS
    }
    elsif (@rtokens > @$tokens) {
      $result = $tb->ok(0, $name);
      my $ff = _format_token($rtokens[$cmp_index+1]);
      diag(<<EOS)
Found longer than expected:
Expected: no entry
Found   : $ff
EOS
    }
  }
  if ($result) {
    $tb->ok(1, $name);
  }
  #print "F: ", _format_token($_), "\n" for @rtokens;
  #print "E: ", _format_token($_), "\n" for @$tokens;

  #is_deeply(\@rtokens, $tokens, $name);

  return $result;
}

sub _format_token {
  my ($token) = @_;

  if (!$token) {
    return "undef";
  }
  else {
    my $result = "[ {" . join('}{', @$token) . "} ]";
    $result =~ s/\n/\\n/g;
    return $result;
  }
}
