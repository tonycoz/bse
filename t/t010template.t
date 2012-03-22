#!perl -w
# Basic tests for Squirrel::Template
use strict;
use Test::More tests => 45;

sub template_test($$$$;$);

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
  template_test("<:if!Str:>FOO<:eif:>", "", "if!Str", \%acts);
  template_test("<:if!Dead:><:str:><:eif:>",
		"* foo\n *<:if!Dead:>ABC<:eif:>", "if!Dead", \%acts);
  template_test("<:if!Noimpl:><:str:><:eif:>",
		"<:if!Noimpl:>ABC<:eif:>", "if!Noimpl", \%acts);

  template_test(<<TEMPLATE, <<OUTPUT, "wrap", \%acts, "in");
<:wrap wraptest.tmpl title=>[cat "foo " [str]], menu => 1, showtitle => "abc" :>Alpha
<:param menu:>
<:param showtitle:>
TEMPLATE
<title>foo ABC</title>
Alpha
1
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
}

sub template_test ($$$$;$) {
  my ($in, $out, $desc, $acts, $stripnl) = @_;

  $stripnl ||= 'none';
  $in =~ s/\n$// if $stripnl eq 'in' || $stripnl eq 'both';
  $out =~ s/\n$// if $stripnl eq 'out' || $stripnl eq 'both';

  my $templater = Squirrel::Template->new(template_dir=>'t/templates');

  my $result = $templater->replace_template($in, $acts);

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
