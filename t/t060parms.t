#!perl -w
use strict;
use Test::More tests => 6;
use Squirrel::Template;

sub format_test($$$$;$);

my $gotmodule = require_ok('DevHelp::Tags');

SKIP: {
  skip "couldn't load module", 5 unless $gotmodule;

  my %acts =
    (
     alpha => 'abc',
     gamma => 'cde',
     upper => 
     sub { 
       my ($args, $acts, $func, $templater) = @_;

       my @parms = DevHelp::Tags->get_parms($args, $acts, $templater);

       uc "@parms";
     },
     lcfirst => 
     sub { 
       my ($args, $acts, $func, $templater) = @_;

       my @parms = DevHelp::Tags->get_parms($args, $acts, $templater);

       lcfirst "@parms";
     },
    );
  format_test(\%acts, "<:upper abc:>", "ABC", 'simple');
  format_test(\%acts, qq/<:upper "abc":>/, "ABC", 'quoted');
  format_test(\%acts, qq/<:upper [alpha]:>/, "ABC", 'function');
  format_test(\%acts, qq/<:upper [alpha] "[alpha beta]":>/,
	      "ABC [ALPHA BETA]", 'combo');
  format_test(\%acts, qq/<:lcfirst [upper [alpha] "[alpha beta]"]:>/,
	      "aBC [ALPHA BETA]", 'nested');
  
}

sub format_test ($$$$;$) {
  my ($acts, $in, $out, $desc, $stripnl) = @_;

  $stripnl ||= 'none';
  $in =~ s/\n$// if $stripnl eq 'in' || $stripnl eq 'both';
  $out =~ s/\n$// if $stripnl eq 'out' || $stripnl eq 'both';

  my $formatter = Squirrel::Template->new();

  my $result = $formatter->replace_template($in, $acts);

  is($result, $out, $desc);
}
