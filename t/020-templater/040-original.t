#!perl -w
# Basic tests for Squirrel::Template
use strict;
use Test::More tests => 167;

sub template_test($$$$;$$);

my $gotmodule = require_ok('Squirrel::Template');

SKIP: {
  skip "couldn't load module", 15 unless $gotmodule;

  my $flag = 0;
  my $str = "ABC";
  my $str2 = "DEF";
  my ($repeat_limit, $repeat_value);

  my %acts =
    (
     ifEq => \&tag_ifeq,
     iterate_repeat_reset =>
     [ \&iter_repeat_reset, \$repeat_limit, \$repeat_value ],
     iterate_repeat =>
     [ \&iter_repeat, \$repeat_limit, \$repeat_value ],
     repeat => \$repeat_value,
     strref => \$str,
     str => $str,
     str2 => $str2,
     with_upper => \&tag_with_upper,
     cat => \&tag_cat,
     ifFalse => 0,
     dead => sub { die "foo\n" },
     noimpl => sub { die "ENOIMPL\n" },
    );
  my %vars =
    (
     a =>
     {
      b =>
      {
       c => "CEE"
      }
     },
     str => $str,
     somelist => [ 'a' .. 'f' ],
     somehash => { qw(a 11 b 12 c 14 e 8) },
     num1 => 101,
     num2 => 202,
     testclass => Squirrel::Template::Expr::WrapClass->new("TestClass"),
     error =>
     {
      noimpl => sub { die "ENOIMPL\n" },
     },
     callback1 => sub {
       my ($cb, $templater, @args) = @_;

       for my $foo ("a" .. "e") {
	 $templater->set_var(foo => $foo);
	 $cb->();
       }
     },
     somecode1 => sub { return "FOO" },
     somecode2 => sub { return [ @_ ] },
    );
  template_test("<:str:>", "ABC", "simple", \%acts);
  template_test("<:strref:>", "ABC", "scalar ref", \%acts);
  $str = "DEF";
  template_test("<:strref:>", "DEF", "scalar ref2", \%acts);
  template_test(<<TEMPLATE, "12345", "iterate", \%acts, "in");
<:iterator begin repeat 1 5:><:repeat:><:iterator end repeat:>
TEMPLATE
  template_test(<<TEMPLATE, "1|2|3|4|5", "iterate sep", \%acts, "in");
<:iterator begin repeat 1 5:><:repeat:><:
iterator separator repeat:>|<:iterator end repeat:>
TEMPLATE
  template_test('<:ifEq [str] "ABC":>YES<:or:>NO<:eif:>', "YES", 
		"cond1", \%acts);
  template_test('<:if Eq [str] "ABC":>YES<:or Eq:>NO<:eif Eq:>', "YES", 
		"cond2", \%acts);
  template_test("<:dead:>", "* foo\n *", "dead", \%acts);
  template_test("<:noimpl:>", "<:noimpl:>", "noimpl", \%acts);
  template_test("<:unknown:>", "<:unknown:>", "unknown tag", \%acts);
  template_test("<:ifDead:><:str:><:or:><:str2:><:eif:>",
		"* foo\n *<:ifDead:>ABC<:or:>DEF<:eif:>", "ifDead", \%acts);
  template_test("<:ifNoimpl:><:str:><:or:><:str2:><:eif:>",
		"<:ifNoimpl:>ABC<:or:>DEF<:eif:>", "ifNoimpl", \%acts);

  template_test("<:if!False:>FOO<:eif:>", "FOO", "if!False", \%acts);
  template_test("<:if !False:>FOO<:eif:>", "FOO", "if !False", \%acts);
  template_test("<:if!Str:>FOO<:eif:>", "", "if!Str", \%acts);
  template_test("<:if!Dead:><:str:><:eif:>",
		"* foo\n *<:if!Dead:>ABC<:eif:>", "if!Dead", \%acts);
  template_test("<:if!Noimpl:><:str:><:eif:>",
		"<:if!Noimpl:>ABC<:eif:>", "if!Noimpl", \%acts);

  template_test(<<TEMPLATE, <<OUTPUT, "wrap", \%acts, "in");
<:wrap wraptest.tmpl title=>[cat "foo " [str]], menu => 1, showtitle => "abc" :>Alpha
<:param menu:>
<:param showtitle:>
<:= params.showtitle :>
TEMPLATE
<title>foo ABC</title>
Alpha
1
abc
abc
OUTPUT

  template_test(<<TEMPLATE, <<OUTPUT, "wrap", \%acts, "both");
Before
<:wrap wraptest.tmpl title=>[cat "foo " [str]], menu => 1, showtitle => "abc" -:>
Alpha
<:param menu:>
<:param showtitle:>
<:-endwrap-:>
After
TEMPLATE
Before
<title>foo ABC</title>
Alpha
1
abc
After
OUTPUT

  template_test(<<TEMPLATE, <<OUTPUT, "wrap with too much parameter text", \%acts, "in");
<:wrap wraptest.tmpl title=>[cat "foo " [str]], menu => 1, showtitle => "abc" junk :>Alpha
<:param menu:>
<:param showtitle:>
TEMPLATE
* WARNING: Extra data after parameters ' junk' *<title>foo ABC</title>
Alpha
1
abc
OUTPUT

  template_test(<<TEMPLATE, <<OUTPUT, "wrap recursive", \%acts, "both");
<:wrap wrapself.tmpl title=>[cat "foo " [str]], menu => 1, showtitle => "abc" :>Alpha
<:param menu:>
<:param showtitle:>
TEMPLATE
* Error starting wrap: Too many levels of wrap for 'wrapself.tmpl' *<title>foo ABC</title>
<title>foo ABC</title>
<title>foo ABC</title>
<title>foo ABC</title>
<title>foo ABC</title>
<title>foo ABC</title>
<title>foo ABC</title>
<title>foo ABC</title>
<title>foo ABC</title>
<title>foo ABC</title>
Alpha
1
abc
OUTPUT

  template_test(<<TEMPLATE, <<OUTPUT, "wrap unknown", \%acts, "both");
<:wrap unknown.tmpl:>
Body
TEMPLATE
* Loading wrap: File unknown.tmpl not found *
OUTPUT

  template_test(<<TEMPLATE, <<OUTPUT, "unwrapped wrap here", \%acts, "both");
before
<:wrap here:>
after
TEMPLATE
before
* wrap here without being wrapped *
after
OUTPUT

  # undefined iterator - replacement should happen on the inside
  template_test(<<TEMPLATE, <<OUTPUT, "undefined iterator", \%acts);
<:iterator begin unknown:>
<:if Eq "1" "1":>TRUE<:or:>FALSE<:eif:>
<:iterator separator unknown:>
<:if Eq "1" "0":>TRUE<:or:>FALSE<:eif:>
<:iterator end unknown:>
TEMPLATE
<:iterator begin unknown:>
TRUE
<:iterator separator unknown:>
FALSE
<:iterator end unknown:>
OUTPUT

  template_test(<<TEMPLATE, <<OUTPUT, "multi wrap", \%acts, "in");
<:wrap wrapinner.tmpl title => "ABC":>
Test
TEMPLATE
<title>ABC</title>

<head1>ABC</head1>

Test
OUTPUT

  my $switch = <<IN;
<:switch:>ignored<:case Eq [strref] "ABC":>ONE<:case Eq [strref] "XYZ":>TWO<:
case default:>DEF<:endswitch:>
IN
  $str = "ABC";
  template_test($switch, "ONE", "switch1", \%acts, "both");
  $str = "XYZ";
  template_test($switch, "TWO", "switch2", \%acts, "both");
  $str = "DEF";
  template_test($switch, "DEF", "switch def", \%acts, "both");

  my $switch2 = <<IN;
<:switch:><:case Eq [strref] "ABC":>ONE<:case Eq [strref] "XYZ":>TWO<:
case default:>DEF<:endswitch:>
IN
  $str = "ABC";
  template_test($switch2, "ONE", "switch without ignored", \%acts, "both");

  template_test(<<IN, <<OUT, "unimplemented switch (by die)", \%acts, "both");
<foo><:strref bar |h:></foo><:switch:><:case Eq [strref] "XYZ":>FAIL<:case Eq [unknown] "ABC":><:endswitch:>
IN
<foo>ABC</foo><:switch:><:case Eq [unknown] "ABC":><:endswitch:>
OUT

  template_test(<<IN, <<OUT, "unimplemented switch (by missing)", \%acts, "both");
<foo><:strref bar |h:></foo><:switch:><:case Eq [strref] "XYZ":>FAIL<:case Unknown:><:str:><:case Eq [unknown] "ABC":><:str2:><:endswitch:>
IN
<foo>ABC</foo><:switch:><:case Unknown:>ABC<:case Eq [unknown] "ABC":>DEF<:endswitch:>
OUT

  template_test(<<IN, <<OUT, "switch with die in case and unknown", \%acts, "both");
<:switch:><:case Eq [strref] "XYZ":>FAIL<:case Dead:><:str:><:case Eq [unknown] "ABC":><:str2:><:endswitch:>
IN
* foo
 *<:switch:><:case Eq [unknown] "ABC":>DEF<:endswitch:>
OUT

  template_test(<<IN, <<OUT, "switch with die no matches", \%acts, "both");
<:switch:><:case Eq [strref] "XYZ":>FAIL<:case Dead:><:str:><:case False:><:str2:><:endswitch:>
IN
* foo
 *
OUT

  template_test(<<IN, <<OUT, "switch with case !", \%acts, "both");
<:switch:><:case !Str:>NOT STR<:case !False:>FALSE<:endswitch:>
IN
FALSE
OUT

  template_test("<:with begin upper:>Alpha<:with end upper:>", "ALPHA", "with", \%acts);

  template_test("<:with begin unknown:>Alpha<:str:><:with end unknown:>", <<EOS, "with", \%acts, "out");
<:with begin unknown:>AlphaABC<:with end unknown:>
EOS

  template_test("<:include doesnt/exist optional:>", "", "optional include", \%acts);
  template_test("<:include doesnt/exist:>", "* cannot find include doesnt/exist in path *", "failed include", \%acts);
  template_test("x<:include included.include:>z", "xyz", "include", \%acts);

  template_test <<IN, <<OUT, "nested in undefined if", \%acts;
<:if Unknown:><:if Eq "1" "1":>Equal<:or Eq:>Not Equal<:eif Eq:><:or Unknown:>false unknown<:eif Unknown:>
IN
<:if Unknown:>Equal<:or Unknown:>false unknown<:eif Unknown:>
OUT
  template_test <<IN, <<OUT, "nested in undefined switch case", \%acts;
<:switch:>
<:case ifUnknown:><:if Eq 1 1:>Equal<:or Eq:>Unequal<:eif Eq:>
<:endswitch:>
IN
<:switch:><:case ifUnknown:>Equal
<:endswitch:>
OUT

  { # using - for removing whitespace
    template_test(<<IN, <<OUT, "space value", \%acts, "both");
<foo>
<:-str-:>
</foo>
<foo>
<:str-:>
</foo>
<foo>
<:str:>
</foo>
IN
<foo>ABC</foo>
<foo>
ABC</foo>
<foo>
ABC
</foo>
OUT

    template_test(<<IN, <<OUT, "space simple cond", \%acts, "both");
<foo>
<:-ifStr:>TRUE<:or-:><:eif-:>
</foo>
<foo2>
<:-ifStr-:>
TRUE
<:-or:><:eif-:>
</foo2>
<foo3>
<:-ifStr-:>
TRUE
<:-or-:>
<:-eif-:>
</foo3>
<foo4>
<:-ifFalse-:>TRUE<:-or-:>FALSE<:-eif-:>
</foo4>
<foo5>
<:-ifFalse-:>
TRUE
<:-or-:>
FALSE
<:-eif-:>
</foo5>
<foo6>
<:ifFalse:>
TRUE
<:or:>
FALSE
<:eif:>
</foo6>
IN
<foo>TRUE</foo>
<foo2>TRUE</foo2>
<foo3>TRUE</foo3>
<foo4>FALSE</foo4>
<foo5>FALSE</foo5>
<foo6>

FALSE

</foo6>
OUT

    template_test(<<IN, <<OUT, "space iterator", \%acts, "both");
<foo>
<:-iterator begin repeat 1 5 -:>
<:-repeat-:>
<:-iterator end repeat -:>
</foo>
<foo2>
<:-iterator begin repeat 1 5 -:>
<:-repeat-:>
<:-iterator separator repeat -:>
,
<:-iterator end repeat -:>
</foo2>
IN
<foo>12345</foo>
<foo2>1,2,3,4,5</foo2>
OUT

    template_test(<<IN, <<OUT, "space switch", \%acts, "both");
<foo>
<:- switch:>

 <:- case default:>FOO
<:- endswitch:>
</foo>
IN
<foo>FOO
</foo>
OUT

    template_test(<<IN, <<OUT, "space complex", \%acts, "both");
<div class="window">
  <h1><:str:></h1>
  <ul class="children list">
    <:iterator begin repeat 1 2:>
    <:- switch:>
    <:- case False:>
    <li class="error message"><:repeat:></li>
    <:case str:>
  </ul>
  <h2><:repeat:></h2>
  <ul class="children list">
    <:- case default:>
    <li><:repeat:></li>
    <:- endswitch:>
    <:iterator end repeat:>
  </ul>
</div>
IN
<div class="window">
  <h1>ABC</h1>
  <ul class="children list">
    
  </ul>
  <h2>1</h2>
  <ul class="children list">
    
  </ul>
  <h2>2</h2>
  <ul class="children list">
    
  </ul>
</div>
OUT
  }

  template_test("<:= unknown :>", "<:= unknown :>", "unknown", \%acts, "", \%vars);
  template_test(<<TEMPLATE, "2", "multi-statement", \%acts, "", \%vars);
<:.set foo = [] :><:% foo.push(1); foo.push(2) :><:= foo.size() -:>
TEMPLATE

  template_test(<<TEMPLATE, "2", "multi-statement no ws", \%acts, "", \%vars);
<:.set foo=[]:><:%foo.push(1);foo.push(2):><:= foo.size() -:>
TEMPLATE

  template_test("<:= str :>", "ABC", "simple exp", \%acts, "", \%vars);
  template_test("<:=str:>", "ABC", "simple exp no ws", \%acts, "", \%vars);
  template_test("<:= a.b.c :>", "CEE", "hash methods", \%acts, "", \%vars);
  template_test(<<IN, <<OUT, "simple set", \%acts, "both", \%vars);
<:.set d = "test" -:><:= d :>
IN
test
OUT
  my @expr_tests =
    (
     [ 'num1 + num2', 303 ],
     [ 'num1 - num2', -101 ],
     [ 'num1 + num2 * 2', 505 ],
     [ 'num2 mod 5', '2' ],
     [ 'num1 / 5', '20.2' ],
     [ 'num1 div 5', 20 ],
     [ '+num1', 101 ],
     [ '-(num1 + num2)', -303 ],
     [ '"hello " _ str', 'hello ABC' ],
     [ 'num1 < num2', 1 ],
     [ 'num1 < 101', '' ],
     [ 'num1 < 100', '' ],
     [ 'num1 > num2', '' ],
     [ 'num2 > num1', 1 ],
     [ 'num1 > 101', '' ],
     [ 'num1 == 101.0', '1' ],
     [ 'num1 == 101', '1' ],
     [ 'num1 == 100', '' ],
     [ 'num1 != 101', '' ],
     [ 'num1 != "101.0"', '' ],
     [ 'num1 != 100', 1 ],
     [ 'num1 >= 101', 1 ],
     [ 'num1 >= 100', 1 ],
     [ 'num1 >= 102', '' ],
     [ 'num1 <= 101', 1 ],
     [ 'num1 <= 100', '' ],
     [ 'num1 <= 102', '1' ],
     [ 'str eq "ABC"', '1' ],
     [ 'str eq "AB"', '' ],
     [ 'str ne "AB"', '1' ],
     [ 'str ne "ABC"', '' ],
     [ 'str.lower', 'abc' ],
     [ 'somelist.size', 6 ],
     [ '[ 4, 2, 3 ].first', 4 ],
     [ '[ 1, 4, 9 ].join(",")', "1,4,9" ],
     [ '[ "xx", "aa" .. "ad", "zz" ].join(" ")', "xx aa ab ac ad zz" ],
     [ '1 ? "TRUE" : "FALSE"', 'TRUE' ],
     [ '0 ? "TRUE" : "FALSE"', 'FALSE' ],
     [ '[ 1 .. 4 ][2]', 3 ],
     [ 'somelist[2]', "c" ],
     [ 'somehash["b"]', "12" ],
     [ 'not 1', '' ],
     [ 'not 1 or 1', 1 ],
     [ 'not 1 and 1', "" ],
     [ '"xabcy" =~ /abc/', 1 ],
     [ '[ "abc" =~ /(.)(.)/ ][1]', "b" ],
     [ '{ "a": 11, "b": 12, "c": 20 }["b"]', 12 ],
     [ '[ 1, 2, 3 ][1]', 2 ],
     [ 'testclass.foo', "[TestClass.foo]" ],

     # WrapScalar
     [ '"foo".length', 3 ],
     [ '"foo".length(1)', "* scalar.length takes no parameters *" ],
     [ '"foo".upper', "FOO" ],
     [ '"foo".upper(1)', "* scalar.upper takes no parameters *" ],
     [ '"Foo".lower', "foo" ],
     [ '"Foo".lower(1)', "* scalar.lower takes no parameters *" ],
     [ '"foo".defined', '1' ],
     [ '"foo".defined(1)', '* scalar.defined takes no parameters *' ],
     [ '"foo".trim', "foo" ],
     [ '" a b ".trim', "a b" ],
     [ '" a b ".trim(1)', "* scalar.trim takes no parameters *" ],
     [ '"a b".split.join("|")', "a|b" ],
     [ '"a,b,c".split(",").join("|")', 'a|b|c' ],
     [ '"a,b,c".split(",",2).join("|")', 'a|b,c' ],
     [ '(10.1).format("%.2f")', "10.10" ],
     [ '(10.1).format("%.2f", 1)', "* scalar.format takes one parameter *" ],
     [ '"str".evaltag', 'ABC' ],
     [ '"cat [str] [str2]".evaltag', 'ABCDEF' ],
     [ '"abc*".quotemeta', "abc\\*" ],
     [ '"abc".quotemeta(1)', "* scalar.quotemeta takes no parameters *" ],
     [ '"abcdef".contains("cde")', 1 ],
     [ '"abcdef".contains("cdf")', "" ],
     [ '"abcdef".contains("cdf",1)', "* scalar.contains requires one parameter *" ],
     [ '"abcdefabcdef".index("cde")', 2 ],
     [ '"abcdefabcdef".index("cdf")', -1 ],
     [ '"abcdefabcdef".index("cde", 5)', 8 ],
     [ '"abc".index("ab",1,2)', '* scalar.index requires one or two parameters *' ],
     [ '"abcdefabcdef".rindex("cde")', 8 ],
     [ '"abcdefabcdef".rindex("cde", 7)', 2 ],
     [ '"abcdefabcdef".rindex("cde", 7, 3)', '* scalar.rindex requires one or two parameters *' ],
     [ "(65).chr", "A" ],
     [ "(10.1).int", 10 ],
     [ "(10).int", 10 ],
     [ "(10).rand < 10 and (10).rand >= 0", 1 ],
     [ "(-10).abs", "10" ],
     [ '(10).floor', 10 ],
     [ '(10.1).floor', 10 ],
     [ '(-10.1).floor', -11 ],
     [ '(10).ceil', 10 ],
     [ '(10.1).ceil', 11 ],
     [ '(-10.1).ceil', -10 ],
     [ '"test".is_list', 0 ],
     [ '"test".is_hash', 0 ],
     [ '"abc".replace(/(.)(.)(.)/, "$3$2$1")', "cba" ],

     # WrapArray
     [ '[ [ 1, 2 ], 3 ].expand.join(",")', "1,2,3" ],
     [ '[ 1, 2 ].is_list', 1 ],
     [ '[ 1, 2 ].is_hash', 0 ],

     # WrapHash
     [ '{ "foo": 1 }.is_list', 0 ],
     [ '{ "foo": 1 }.is_hash', 1 ],
    );
  for my $test (@expr_tests) {
    my ($expr, $result) = @$test;

    template_test("<:= $expr :>", $result, "expr: $expr", \%acts, "", \%vars);
  }

  template_test(<<IN, "", "define no use", \%acts, "both", \%vars);
<:-.define foo:>
<:.end-:>
<:-.define bar:>
<:.end define-:>
IN
  template_test(<<IN, "avaluebvalue", "define with call", \%acts, "both", \%vars);
<:-.define foo:>
<:-= avar -:>
<:.end-:>
<:.call "foo", "avar":"avalue"-:>
<:.call "foo",
  "avar":"bvalue"-:>
IN
  template_test(<<IN, "other value", "external call", \%acts, "", \%vars);
<:.call "called.tmpl", "avar":"other value"-:>
IN
  template_test(<<IN, "This was preloaded", "call preloaded", \%acts, "both", \%vars);
<:.call "preloaded"-:>
IN
  template_test(<<IN, <<OUT, "simple .for", \%acts, "", \%vars);
<:.for x in [ "a" .. "d" ] -:>
Value: <:= x :> Index: <:= loop.index :> Count: <:= loop.count:> Prev: <:= loop.prev :> Next: <:= loop.next :> Even: <:= loop.even :> Odd: <:= loop.odd :> Parity: <:= loop.parity :> is_first: <:= loop.is_first :> is_last: <:= loop.is_last :>-
<:.end-:>
IN
Value: a Index: 0 Count: 1 Prev:  Next: b Even:  Odd: 1 Parity: odd is_first: 1 is_last: -
Value: b Index: 1 Count: 2 Prev: a Next: c Even: 1 Odd:  Parity: even is_first:  is_last: -
Value: c Index: 2 Count: 3 Prev: b Next: d Even:  Odd: 1 Parity: odd is_first:  is_last: -
Value: d Index: 3 Count: 4 Prev: c Next:  Even: 1 Odd:  Parity: even is_first:  is_last: 1-
OUT
  template_test(<<IN, <<OUT, "simple .if", \%acts, "", \%vars);
<:.if "a" eq "b" :>FAIL<:.else:>SUCCESS<:.end:>
<:.if "a" eq "a" :>SUCCESS<:.else:>FAIL<:.end:>
<:.if "a" eq "c" :>FAIL1<:.elsif "a" eq "a":>SUCCESS<:.else:>FAIL2<:.end:>
IN
SUCCESS
SUCCESS
SUCCESS
OUT
  template_test(<<IN, <<OUT, "unknown .if", \%acts, "", \%vars);
<:.if unknown:>TRUE<:.end:>
<:.if "a" eq "a":>TRUE<:.elsif unknown:>TRUE<:.end:>
<:.if "a" eq "b" :>TRUE<:.elsif unknown:>TRUE<:.end:>
<:.if "a" ne "a" :>TRUE<:.elsif 0:>ELIF<:.elsif unknown:>TRUE<:.end:>
IN
<:.if unknown:>TRUE<:.end:>
TRUE
<:.if 0 :><:.elsif unknown:>TRUE<:.end:>
<:.if 0 :><:.elsif unknown:>TRUE<:.end:>
OUT

  template_test(<<IN, <<OUT, "stack overflow on .call", \%acts, "", \%vars);
<:.define foo:>
<:-.call "foo"-:>
<:.end:>
<:-.call "foo"-:>
IN
Error opening scope for call: Too many scope levels
Backtrace:
  .call 'foo' from test:1
  .call 'foo' from test:1
  .call 'foo' from test:1
  .call 'foo' from test:1
  .call 'foo' from test:1
  .call 'foo' from test:1
  .call 'foo' from test:1
  .call 'foo' from test:1
  .call 'foo' from test:1
  .call 'foo' from test:1
  .call 'foo' from test:1
  .call 'foo' from test:1
  .call 'foo' from test:1
  .call 'foo' from test:1
  .call 'foo' from test:1
  .call 'foo' from test:1
  .call 'foo' from test:1
  .call 'foo' from test:1
  .call 'foo' from test:1
  .call 'foo' from test:1
  .call 'foo' from test:1
  .call 'foo' from test:1
  .call 'foo' from test:1
  .call 'foo' from test:1
  .call 'foo' from test:1
  .call 'foo' from test:1
  .call 'foo' from test:1
  .call 'foo' from test:1
  .call 'foo' from test:1
  .call 'foo' from test:1
  .call 'foo' from test:1
  .call 'foo' from test:1
  .call 'foo' from test:1
  .call 'foo' from test:1
  .call 'foo' from test:1
  .call 'foo' from test:1
  .call 'foo' from test:1
  .call 'foo' from test:1
  .call 'foo' from test:1
  .call 'foo' from test:1
  .call 'foo' from test:1
  .call 'foo' from test:1
  .call 'foo' from test:1
  .call 'foo' from test:1
  .call 'foo' from test:1
  .call 'foo' from test:1
  .call 'foo' from test:1
  .call 'foo' from test:3
OUT

  template_test(<<IN, <<OUT, "evaltags", \%acts, "", \%vars);
<:= "str".evaltag :>
<:= "cat [str] [str2]".evaltag :>
IN
ABC
ABCDEF
OUT

template_test(<<IN, <<OUT, "hash methods", \%acts, "", \%vars);
<:.set foo = { "abc": 1, "def":2 } -:>
<:% foo.set("ghi", 3) -:>
ghi: <:= foo.ghi :>
keys: <:= foo.keys.sort.join(",") :>
size: <:= foo.size :>
values: <:= foo.values.sort.join(",") :>
<:.for i in foo.list -:>
<:= i.key _ "=" _ i.value :>
<:.end for-:>
IN
ghi: 3
keys: abc,def,ghi
size: 3
values: 1,2,3
abc=1
def=2
ghi=3
OUT

template_test(<<IN, <<OUT, "array methods", \%acts, "", \%vars);
<:.set foo = [ 1, 2, 4 ] -:>
<:% foo.set(2, 3) -:>
2: <:= foo[2] :>
IN
2: 3
OUT

  template_test(<<IN, <<OUT, "set undef", \%acts, "", \%vars);
<:.set foo = unknown :>
<:.set bar = error.noimpl :>
IN
<:.set foo = unknown :>
<:.set bar = error.noimpl :>
OUT

  template_test(<<IN, <<OUT, "iterateover", \%acts, "", \%vars);
<:.iterateover callback1-:>
<:= foo -:>
<:.end:>
IN
abcde
OUT

  template_test(<<'IN', <<OUT, "globals default variable", \%acts, "", \%vars);
<:.set globals.foo = "test" -:>
<:= globals.foo :>
<:.set name="foo" -:>
<:= testclass.$name :>
<:= testclass.$name() :>
<:= testclass.$name(1) :>
IN
test
[TestClass.foo]
[TestClass.foo]
[TestClass.foo]
OUT

  template_test(<<'IN', <<OUT, "function calls", \%acts, "", \%vars);
<:= somecode1() :>
<:= somecode2().join(",") :>
<:= somecode2("a", "b").join(",") :>
IN
FOO

a,b
OUT
}

sub template_test ($$$$;$$) {
  my ($in, $out, $desc, $acts, $stripnl, $vars) = @_;

  $stripnl ||= 'none';
  $in =~ s/\n$// if $stripnl eq 'in' || $stripnl eq 'both';
  $out =~ s/\n$// if $stripnl eq 'out' || $stripnl eq 'both';

  my $templater = Squirrel::Template->new
    (
     template_dir=>'t/templates',
     preload => "preload.tmpl"
    );

  my $result = $templater->replace_template($in, $acts, undef, "test", $vars);

  is($result, $out, $desc);
}

sub iter_repeat_reset {
  my ($rlimit, $rvalue, $args) = @_;

  ($$rvalue, $$rlimit) = split ' ', $args;
  --$$rvalue;
}

sub iter_repeat {
  my ($rlimit, $rvalue) = @_;

  ++$$rvalue <= $$rlimit;
}

sub tag_ifeq {
  my ($args, $acts, $func, $templater) = @_;

  my @args = get_expr($args, $acts, $templater);

  @args >= 2
    or die "ifEq takes 2 arguments";

  $args[0] eq $args[1];
}

sub get_expr {
  my ($origargs, $acts, $templater) = @_;

  my @values;
  my $args = $origargs;
  while ($args) {
    if ($args =~ s/\s*\[([^\[\]]+)\]\s*//) {
      my $expr = $1;
      my ($func, $funcargs) = split ' ', $expr, 2;
      exists $acts->{$func} or die "ENOIMPL\n";
      push @values, scalar $templater->perform($acts, $func, $funcargs, $expr);
    }
    elsif ($args =~ s/\s*\"((?:[^\"\\]|\\[\"\\]|\"\")*)\"\s*//) {
      my $str = $1;
      $str =~ s/(?:\\([\"\\])|\"(\"))/$1 || $2/eg;
      push @values, $str;
    }
    elsif ($args =~ s/\s*(\S+)\s*//) {
      push @values, $1;
    }
    else {
      print "Arg parse failure with '$origargs' at '$args'\n";
      exit;
    }
  }
  
  @values;
}

sub tag_with_upper {
  my ($args, $text) = @_;

  return uc($text);
}

sub tag_cat {
  my ($args, $acts, $func, $templater) = @_;

  return join "", $templater->get_parms($args, $acts);
}

package TestClass;

sub foo {
  return "[TestClass.foo]";
}
