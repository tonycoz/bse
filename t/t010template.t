#!perl -w
# Basic tests for Squirrel::Template
use strict;
use Test::More tests => 18;

sub template_test($$$$;$);

my $gotmodule = require_ok('Squirrel::Template');

SKIP: {
  skip "couldn't load module", 15 unless $gotmodule;

  my $flag = 0;
  my $str = "ABC";
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
     with_upper => \&tag_with_upper,
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
  template_test('<:wrap wraptest.tmpl title=>"foo [str]":>Alpha', <<OUTPUT,
<title>foo ABC</title>
Alpha
OUTPUT
		"wrap", \%acts);
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

  template_test(<<IN, <<OUT, "unimplemented switch", \%acts, "both");
<:switch:><:case Eq [strref] "XYZ":>FAIL<:case Eq [unknown] "ABC":><:endswitch:>
IN
<:switch:><:case Eq [unknown] "ABC":><:endswitch:>
OUT

  template_test("<:with begin upper:>Alpha<:with end upper:>", "ALPHA", "with", \%acts);
  template_test("<:include doesnt/exist optional:>", "", "optional include", \%acts);
  template_test("<:include doesnt/exist:>", "** cannot find include doesnt/exist in path **", "failed include", \%acts);
  template_test("x<:include included.include:>z", "xyz", "include", \%acts);
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
