#!perl -w
use strict;
use Test::More tests => 34;
use Squirrel::Template;

sub test_parse($$$);

{
  # test the API
  my $templater = Squirrel::Template->new();
  my $t = Squirrel::Template::Tokenizer->new(<<EOS, "<text>", $templater);
test <:foo bar:><:with end bar:><:with unknown:>
EOS
  my $p = Squirrel::Template::Parser->new($t, $templater);
  ok($p, "make a parser");
  my $tree = $p->parse;
  is_deeply($tree,
	    [ comp => "", 1, "<text>",
	      [ content => "test ", 1, "<text>" ],
	      [ tag => "<:foo bar:>", 1, "<text>", "foo", "bar" ],
	      [ error => "<:with end bar:>", 1, "<text>", "Expected eof but found withend" ],
	      [ error => "<:with unknown:>", 1, "<text>", "Syntax error: incorrect use of 'with'" ],
	      [ content => "\n", 1, "<text>" ],
	    ], "check parse result");
  is_deeply([ $p->errors ],
	    [
	      [ error => "<:with end bar:>", 1, "<text>", "Expected eof but found withend" ],
	     [ error => "<:with unknown:>", 1, "<text>", "Syntax error: incorrect use of 'with'" ],
	    ], "check errors");
}

test_parse(<<EOS,
simple text
EOS
	   [ "content", "simple text\n", 1, "<string>" ], "simple");

test_parse(<<EOS,
tag test <:sometag foo -:>
EOS
	   [ comp => "", 1, "<string>",
	     [ content => "tag test ", 1, "<string>" ],
	     [ tag => "<:sometag foo -:>\n", 1, "<string>", "sometag", "foo" ]
	   ], "simple tag");

test_parse(<<EOS,
<:if Foo:>TRUE<:or:>FALSE<:eif -:>
EOS
	   [ cond => "<:if Foo:>", 1, "<string>", "Foo", "",
	     [ content => "TRUE", 1, "<string>" ],
	     [ content => "FALSE", 1, "<string>" ],
	     [ or => "<:or:>", 1, "<string>", '' ],
	     [ eif => "<:eif -:>\n", 1, "<string>", '' ],
	   ], "simple cond");

test_parse(<<EOS,
<:if Foo:>TRUE<:or Foo:>FALSE<:eif Foo -:>
EOS
	   [ cond => "<:if Foo:>", 1, "<string>", "Foo", "",
	     [ content => "TRUE", 1, "<string>" ],
	     [ content => "FALSE", 1, "<string>" ],
	     [ or => "<:or Foo:>", 1, "<string>", 'Foo' ],
	     [ eif => "<:eif Foo -:>\n", 1, "<string>", 'Foo' ],
	   ], "named cond with named or/eif");

test_parse(<<EOS,
<:if Foo:>TRUE<:eif -:>
EOS
	   [ cond => "<:if Foo:>", 1, "<string>", "Foo", "",
	     [ content => "TRUE", 1, "<string>" ],
	     [ empty => "", 1, "<string>" ],
	     [ empty => "", 1, "<string>" ],
	     [ eif => "<:eif -:>\n", 1, "<string>", "" ],
	   ], "simple cond, no else");

test_parse(<<EOS,
<:if Foo:>TRUE<:or -:>
EOS
	   [ comp => "", 1, "<string>",
	     [ cond => "<:if Foo:>", 1, "<string>", "Foo", "",
	       [ content => "TRUE", 1, "<string>" ],
	       [ empty => "", 2, "<string>" ],
	       [ or => "<:or -:>\n", 1, "<string>", '' ],
	       [ eif => "<:eif:>", 2, "<string>" ], # synthesized
	     ],
	     [ error => "", 2, "<string>", "Expected 'eif' tag for if starting <string>:1 but found eof" ]
	   ], "simple cond, with or, no eif");

test_parse(<<EOS,
<:if Foo:>TRUE
EOS
	   [ comp => "", 1, "<string>",
	     [ cond => "<:if Foo:>", 1, "<string>", "Foo", "",
	       [ content => "TRUE\n", 1, "<string>" ],
	       [ empty => "", 2, "<string>" ],
	       [ empty => "", 2, "<string>" ],
	       [ eif => "", 2, "<string>" ],
	     ],
	     [ error => "", 2, "<string>", "Expected 'or' or 'eif' tag for if starting <string>:1 but found eof" ]
	   ], "simple cond, with or, no eif");

test_parse(<<EOS,
<:if Foo:>TRUE<:or Bar:>
EOS
	   [ comp => "", 1, "<string>",
	     [ cond => "<:if Foo:>", 1, "<string>", "Foo", "",
	       [ content => "TRUE", 1, "<string>" ],
	       [ content => "\n", 1, "<string>" ],
	       [ or => "<:or Bar:>", 1, "<string>", "Bar" ],
	       [ eif => "<:eif:>", 2, "<string>" ],
	     ],
	     [ error => "", 1, "<string>", "'or' or 'eif' for 'if Foo' starting <string>:1 expected but found 'or Bar'" ],
	     [ error => "", 2, "<string>", "Expected 'eif' tag for if starting <string>:1 but found eof" ]
	   ], "simple cond, with or, no eif");

test_parse("<:if Foo:>TRUE<:or Bar:>FALSE<:eif:>",
	   [ comp => "", 1, "<string>",
	     [ cond => "<:if Foo:>", 1, "<string>", "Foo", "",
	       [ content => "TRUE", 1, "<string>" ],
	       [ content => "FALSE", 1, "<string>" ],
	       [ or => "<:or Bar:>", 1, "<string>", "Bar" ],
	       [ eif => "<:eif:>", 1, "<string>", "" ],
	     ],
	     [ error => "", 1, "<string>", "'or' or 'eif' for 'if Foo' starting <string>:1 expected but found 'or Bar'" ],
	   ], "if with or name mismatch");

test_parse("<:if Foo:>TRUE<:or:>FALSE<:eif Bar:>",
	   [ comp => "", 1, "<string>",
	     [ cond => "<:if Foo:>", 1, "<string>", "Foo", "",
	       [ content => "TRUE", 1, "<string>" ],
	       [ content => "FALSE", 1, "<string>" ],
	       [ or => "<:or:>", 1, "<string>", "" ],
	       [ eif => "<:eif Bar:>", 1, "<string>", "Bar" ],
	     ],
	     [ error => "", 1, "<string>", "'eif' for 'if Foo' starting <string>:1 expected but found 'eif Bar'" ],
	   ], "if with or, eif name mismatch");

test_parse("<:if Foo:>TRUE<:eif Bar:>",
	   [ comp => "", 1, "<string>",
	     [ cond => "<:if Foo:>", 1, "<string>", "Foo", "",
	       [ content => "TRUE", 1, "<string>" ],
	       [ empty => "", 1, "<string>" ],
	       [ empty => "", 1, "<string>" ],
	       [ eif => "<:eif Bar:>", 1, "<string>", "Bar" ],
	     ],
	     [ error => "", 1, "<string>", "'or' or 'eif' for 'if Foo' starting <string>:1 expected but found 'eif Bar'" ],
	   ], "if with no or, eif name mismatch");

test_parse("<:if Foo:>TRUE<:eif Foo:>",
	   [ cond => "<:if Foo:>", 1, "<string>", "Foo", "",
	     [ content => "TRUE", 1, "<string>" ],
	     [ empty => "", 1, "<string>" ],
	     [ empty => "", 1, "<string>" ],
	     [ eif => "<:eif Foo:>", 1, "<string>", "Foo" ],
	   ], "if with no or, eif name matches");

test_parse(<<EOS,
<:iterator begin foo:>LOOP
<:- iterator end foo:>
EOS
	   [ comp => "", 1, "<string>",
	     [ iterator => "<:iterator begin foo:>", 1, "<string>", "foo", "",
	       [ content => "LOOP", 1, "<string>" ],
	       [ empty => "", 1, "<string>" ],
	       [ empty => "", 1, "<string>" ],
	       [ itend => "\n<:- iterator end foo:>", 1, "<string>", "foo" ],
	     ],
	     [ content => "\n", 2, "<string>" ]
	   ], "simple iterator");

test_parse(<<EOS,
<:iterator begin foo [bar]:>LOOP
<:- iterator separator foo:>SEP
<:- iterator end foo:>
EOS
	   [ comp => "", 1, "<string>",
	     [ iterator => "<:iterator begin foo [bar]:>", 1, "<string>", "foo", "[bar]",
	       [ content => "LOOP", 1, "<string>" ],
	       [ content => "SEP", 2, "<string>" ],
	       [ itsep => "\n<:- iterator separator foo:>", 1, "<string>", "foo" ],
	       [ itend => "\n<:- iterator end foo:>", 2, "<string>", "foo" ],
	     ],
	     [ content => "\n", 3, "<string>" ]
	   ], "iterator with sep");

test_parse(<<EOS,
<:iterator begin foo [bar]:>LOOP
<:- iterator separator bar:>SEP
<:- iterator end foo:>
EOS
	   [ comp => "", 1, "<string>",
	     [ iterator => "<:iterator begin foo [bar]:>", 1, "<string>", "foo", "[bar]",
	       [ content => "LOOP", 1, "<string>" ],
	       [ content => "SEP", 2, "<string>" ],
	       [ itsep => "\n<:- iterator separator bar:>", 1, "<string>", "bar" ],
	       [ itend => "\n<:- iterator end foo:>", 2, "<string>", "foo" ],
	     ],
	     [ error => "", 1, "<string>", "Expected 'iterator separator foo' for 'iterator begin foo' at <string>:1 but found 'iterator separator bar'" ],
	     [ content => "\n", 3, "<string>" ]
	   ], "iterator with sep with name mismatch");

test_parse(<<EOS,
<:iterator begin foo:>LOOP
<:- iterator end bar:>
EOS
	   [ comp => "", 1, "<string>",
	     [ iterator => "<:iterator begin foo:>", 1, "<string>", "foo", "",
	       [ content => "LOOP", 1, "<string>" ],
	       [ empty => "", 1, "<string>" ],
	       [ empty => "", 1, "<string>" ],
	       [ itend => "\n<:- iterator end bar:>", 1, "<string>", "bar" ],
	     ],
	     [ error => "", 1, "<string>", "Expected 'iterator end foo' for 'iterator begin foo' at <string>:1 but found 'iterator end bar'" ],
	     [ content => "\n", 2, "<string>" ]
	   ], "simple iterator, name mismatch");

test_parse(<<EOS,
<:iterator begin foo:>LOOP
MORE
EOS
	   [ comp => "", 1, "<string>",
	     [ iterator => "<:iterator begin foo:>", 1, "<string>", "foo", "",
	       [ content => "LOOP\nMORE\n", 1, "<string>" ],
	       [ empty => "", 3, "<string>" ],
	       [ empty => "", 3, "<string>" ],
	       [ itend => "<:iterator end foo:>", 3, "<string>" ],
	     ],
	     [ error => "", 3, "<string>", "Expected 'iterator separator foo' or 'iterator end foo' for 'iterator begin foo' at <string>:1 but found eof" ],
	   ], "simple iterator, unterminated");

test_parse(<<EOS,
<:iterator begin foo:>LOOP
<:iterator separator foo:>MORE
EOS
	   [ comp => "", 1, "<string>",
	     [ iterator => "<:iterator begin foo:>", 1, "<string>", "foo", "",
	       [ content => "LOOP\n", 1, "<string>" ],
	       [ content => "MORE\n", 2, "<string>" ],
	       [ itsep => "<:iterator separator foo:>", 2, "<string>", "foo" ],
	       [ itend => "<:iterator end foo:>", 3, "<string>" ],
	     ],
	     [ error => "", 3, "<string>", "Expected 'iterator end foo' for 'iterator begin foo' at <string>:1 but found eof" ],
	   ], "iterator with separator, unterminated");

test_parse(<<EOS,
<:iterator begin foo:>LOOP
<:iterator separator foo:>MORE
<:iterator end bar:>
EOS
	   [ comp => "", 1, "<string>",
	     [ iterator => "<:iterator begin foo:>", 1, "<string>", "foo", "",
	       [ content => "LOOP\n", 1, "<string>" ],
	       [ content => "MORE\n", 2, "<string>" ],
	       [ itsep => "<:iterator separator foo:>", 2, "<string>", "foo" ],
	       [ itend => "<:iterator end bar:>", 3, "<string>", "bar" ],
	     ],
	     [ error => "", 3, "<string>", "Expected 'iterator end foo' for 'iterator begin foo' at <string>:1 but found 'iterator end bar'" ],
	     [ content => "\n", 3, "<string>" ],
	   ], "iterator with separator, name mismatch on end");

test_parse(<<EOS,
<:with begin foo:>LOOP
<:- with end foo:>
EOS
	   [ comp => "", 1, "<string>",
	     [ with => "<:with begin foo:>", 1, "<string>", "foo", "",
	       [ content => "LOOP", 1, "<string>" ],
	       [ withend => "\n<:- with end foo:>", 1, "<string>", "foo" ],
	     ],
	     [ content => "\n", 2, "<string>" ]
	   ], "simple wwith");

test_parse(<<EOS,
<:with begin foo:>LOOP
<:- with end bar:>
EOS
	   [ comp => "", 1, "<string>",
	     [ with => "<:with begin foo:>", 1, "<string>", "foo", "",
	       [ content => "LOOP", 1, "<string>" ],
	       [ withend => "\n<:- with end bar:>", 1, "<string>", "bar" ],
	     ],
	     [ error => "", 1, "<string>", "Expected 'with end foo' for 'with begin foo' at <string>:1 but found 'with end bar'" ],
	     [ content => "\n", 2, "<string>" ]
	   ], "simple with, name mismatch");

test_parse(<<EOS,
<:with begin foo:>LOOP
EOS
	   [ comp => "", 1, "<string>",
	     [ with => "<:with begin foo:>", 1, "<string>", "foo", "",
	       [ content => "LOOP\n", 1, "<string>" ],
	       [ withend => "<:with end foo:>", 2, "<string>" ],
	     ],
	     [ error => "", 2, "<string>", "Expected 'with end foo' for 'with begin foo' at <string>:1 but found eof" ],
	   ], "simple with, unterminated");

test_parse(<<EOS,
<:switch:>IGNORED
<:case Foo:>FOO
<:case Bar x:>BAR
<:case default:>DEFAULT
<:endswitch:>
EOS
	   [ comp => "", 1, "<string>",
	     [ switch => "<:switch:>", 1, "<string>", "",
	       [ 
		[ 
		 [ case => "<:case Foo:>", 2, "<string>", "Foo", "" ],
		 [ content => "FOO\n", 2, "<string>" ],
		],
		[
		 [ case => "<:case Bar x:>", 3, "<string>", "Bar", "x" ],
		 [ content => "BAR\n", 3, "<string>" ],
		],
		[
		 [ case => "<:case default:>", 4, "<string>", "default", "" ],
		 [ content => "DEFAULT\n", 4, "<string>" ],
		],
	       ],
	       [ endswitch => "<:endswitch:>", 5, "<string>", "" ],
	     ],
	     [ content => "\n", 5, "<string>" ]
	   ], "simple switch");

test_parse("<:switch:><:case Foo:>",
	   [ comp => "", 1, "<string>",
	     [ switch => "<:switch:>", 1, "<string>", "",
	       [
		[
		 [ case => "<:case Foo:>", 1, "<string>", "Foo", "" ],
		 [ empty => "", 1, "<string>" ],
		]
	       ],
	       [ endswitch => "<:endswitch:>", 1, "<string>" ],
	     ],
	     [ error => "", 1, "<string>", "Expected case or endswitch for switch starting <string>:1 but found eof" ],
	   ], "unterminated switch");

test_parse(<<EOS,
<:wrap base.tmpl foo => "1":>WRAPPED
EOS
	   [ wrap => q(<:wrap base.tmpl foo => "1":>), 1, "<string>",
	     'base.tmpl', 'foo => "1"',
	     [ content => "WRAPPED\n", 1, "<string>" ],
	   ], "endless wrap");

test_parse(<<EOS,
<:wrap base.tmpl foo => "1":>WRAPPED
<:endwrap:>
EOS
	   [ comp => "", 1, "<string>",
	     [ wrap => q(<:wrap base.tmpl foo => "1":>), 1, "<string>",
	       'base.tmpl', 'foo => "1"',
	       [ content => "WRAPPED\n", 1, "<string>" ],
	     ],
	     [ content => "\n", 2, "<string>" ]
	   ], "ended wrap");

test_parse(<<EOS,
<:wrap base.tmpl foo => "1":>WRAPPED
<:with end foo:>
EOS
	   [ comp => "", 1, "<string>",
	     [ wrap => q(<:wrap base.tmpl foo => "1":>), 1, "<string>",
	       'base.tmpl', 'foo => "1"',
	       [ content => "WRAPPED\n", 1, "<string>" ],
	     ],
	     [ error => "", 2, "<string>", "Expected 'endwrap' or eof for wrap started <string>:1 but found withend" ],
	     [ error => "<:with end foo:>", 2, "<string>", "Expected eof but found withend" ],
	     [ content => "\n", 2, "<string>" ]
	   ], "badly terminated wrap");

test_parse("abc <:with end foo:> def",
	   [ comp => "", 1, "<string>",
	     [ content => "abc ", 1, "<string>" ],
	     [ error => "<:with end foo:>", 1, "<string>", "Expected eof but found withend" ],
	     [ content => " def", 1, "<string>" ],
	   ], "with end without with");

test_parse("abc <:*&:> def",
	   [ comp => "", 1, "<string>",
	     [ content => "abc ", 1, "<string>" ],
	     [ error => "<:*&:>", 1, "<string>", "Syntax error: unknown tag start '*&'" ],
	     [ content => " def", 1, "<string>" ],
	   ], "passthrough of error tokens");

test_parse("abc <:# some comment:> def",
	   [ comp => "", 1, "<string>",
	     [ content => "abc ", 1, "<string>" ],
	     [ content => " def", 1, "<string>" ],
	   ], "comment tags are dropped");

test_parse("abc <:wrap here:> def",
	   [ comp => "", 1, "<string>",
	     [ content => "abc ", 1, "<string>" ],
	     [ wraphere => "<:wrap here:>", 1, "<string>" ],
	     [ content => " def", 1, "<string>" ],
	   ], "wrap here");

sub test_parse($$$) {
  my ($text, $parse, $name) = @_;

  my $tmpl = Squirrel::Template->new();
  my $tok = Squirrel::Template::Tokenizer->new($text, "<string>", $tmpl);
  my $parser = Squirrel::Template::Parser->new($tok, $tmpl);

  my $rtree = $parser->parse;

  use Data::Dumper;
$Data::Dumper::Indent = 0;
print Dumper($rtree), "\n", Dumper($parse), "\n";

  print Squirrel::Template::Deparser->deparse($rtree), "\n";

  return is_deeply($rtree, $parse, $name);
}
