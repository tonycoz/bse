#!perl -w
use strict;
use Squirrel::Template::Expr;
use Test::More tests => 20;
use Data::Dumper;

test_tok("abc",
	 [
	  [ id => "abc", "abc" ],
	  [ eof => "" ],
	 ], "simple id");

test_tok("a.b + 1.0",
	 [
	  [ id => "a", "a" ],
	  [ "op." => "." ],
	  [ id => "b ", "b" ],
	  [ "op+" => "+ " ],
	  [ num => "1.0", "1.0" ],
	  [ eof => "" ],
	 ], "simple expr");

test_tok("1 .1 1e+10 .1e-10 5e2 0xff 0b101 0o11",
	 [
	  [ num => "1 ", 1 ],
	  [ num => ".1 ", ".1" ],
	  [ num => "1e+10 ", "1e+10" ],
	  [ num => ".1e-10 ", ".1e-10" ],
	  [ num => "5e2 ", "5e2" ],
	  [ num => "0xff ", 255 ],
	  [ num => "0b101 ", 5 ],
	  [ num => "0o11", 9 ],
	  [ eof => "" ],
	 ], "numbers");

test_tok('"-\n-\"-\N{LATIN CAPITAL LETTER A}-\x41-\x{0041}-"',
	 [
	  [ str => '"-\n-\"-\N{LATIN CAPITAL LETTER A}-\x41-\x{0041}-"', 
	    "-\n-\"-A-A-A-" ],
	  [ eof => "" ],
	 ], "string with escapes");

test_tok(" 'abc' ",
	 [
	  [ str => " 'abc' ", 'abc' ],
	  [ eof => "" ],
	 ], "no escape strings");

test_tok("+ - == != > >= < <= eq ne lt le gt ge . _",
	 [
	  [ "op+" => "+ " ],
	  [ "op-" => "- " ],
	  [ "op==" => "== " ],
	  [ "op!=" => "!= " ],
	  [ "op>" => "> " ],
	  [ "op>=", => ">= " ],
	  [ "op<", "< " ],
	  [ "op<=", "<= " ],
	  [ "opeq" => "eq " ],
	  [ "opne" => "ne " ],
	  [ "oplt" => "lt " ],
	  [ "ople" => "le " ],
	  [ "opgt" => "gt " ],
	  [ "opge" => "ge " ],
	  [ "op." => ". " ],
	  [ "op_" => "_" ],
	  [ eof => "" ],
	 ], "operators");

test_tok("(10.1).foo",
	 [
	  [ "op(", "(" ],
	  [ num => "10.1", "10.1" ],
	  [ "op)", ")" ],
	  [ "op." => "." ],
	  [ id => "foo", "foo" ],
	  [ eof => "" ],
	 ], "parens");

test_parse("1+1",
	   [ "add",
	     [ const => 1 ],
	     [ const => 1 ],
	   ], "add");

test_parse("a+b*c",
	   [ "add",
	     [ var => "a" ],
	     [ "mult",
	       [ var => "b" ],
	       [ var => "c" ],
	     ]
	   ], "bin + and *");

test_parse("a-b/c",
	   [ "subtract",
	     [ var => "a" ],
	     [ "fdiv",
	       [ var => "b" ],
	       [ var => "c" ],
	     ]
	   ], "bin - and /");

test_parse("a div b mod c",
	   [ "mod",
	     [ "div",
	       [ var => "a" ],
	       [ var => "b" ],
	     ],
	     [ var => "c" ],
	   ], "div and mod");

test_parse("a/(b*c)",
	   [ "fdiv",
	     [ var => "a" ],
	     [ "mult",
	       [ var => "b" ],
	       [ var => "c" ],
	     ]
	   ], "() precedence");

test_parse("a _ 'abc'",
	   [ "concat",
	     [ var => "a" ],
	     [ const => "abc" ],
	   ], "string concat");

test_parse("a[b]",
	   [ "subscript",
	     [ var => "a" ],
	     [ var => "b" ],
	   ], "subscript");

test_parse("+a * -b",
	   [ "mult",
	     [ var => "a" ],
	     [ uminus =>
	       [ var => "b" ],
	     ]
	   ], "uminus/plus");

test_parse("!a and not b or c < d",
	   [ "or",
	     [ and =>
	       [ not =>
		 [ var => "a" ],
	       ],
	       [ not =>
		 [ var => "b" ],
	       ],
	     ],
	     [ "nlt" =>
	       [ var => "c" ],
	       [ var => "d" ],
	     ]
	   ], "boolean and rel ops");

test_parse("[ a, b .. c, d ]",
	   [ "list",
	     [
	      [ var => "a" ],
	      [ range =>
		[ var => "b" ],
		[ var => "c" ],
	      ],
	      [ var => "d" ],
	     ],
	   ], "list with range");


test_parse("a.b.c().d(1).e(1,2)",
	   [ call =>
	     "e",
	     [ call =>
	       "d",
	       [ call =>
		 "c",
		 [ call =>
		   "b",
		   [ var => "a" ],
		   [ ]
		 ],
		 []
	       ],
	       [
		[ const => 1 ]
	       ]
	     ],
	     [
	      [ const => 1 ],
	      [ const => 2 ],
	     ]
	   ], "method calls");

test_parse('a.b =~ /a.*\/b/',
	   [ "match" =>
	     [ call =>
	       "b",
	       [ var => "a" ],
	       []
	     ],
	     [ const => qr(a.*\/b) ],
	   ], "regexp match");

test_parse("(10.1).foo",
	   [ call =>
	     "foo",
	     [ const => 10.1 ],
	     [],
	   ], "method on parens expr");

sub test_tok {
  my ($str, $tokens, $name) = @_;

  my $tok = Squirrel::Template::Expr::Tokenizer->new($str);
  my @result;
  while (my $t = $tok->get) {
    push @result, $t;
  }

  unless(is_deeply(\@result, $tokens, $name)) {
    print Dumper \@result;
  }
}

sub test_parse {
  my ($str, $expr, $name) = @_;

  eval {
    my $parser = Squirrel::Template::Expr::Parser->new;
    my $got = $parser->parse($str);
    unless (is_deeply($got, $expr, $name)) {
      print Dumper($got);
    }
  } and return 1;
  fail($name);
  diag Dumper($@);
}
