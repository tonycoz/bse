#!perl
use strict;
use warnings;
use Test::More;
use ExtUtils::Manifest qw(maniread);
use Squirrel::Template;

my $mani = maniread();

$| = 1;
my @templates = map m(^site/templates/(.*)$),
  sort grep m(^site/templates/.*\.tmpl$), keys %$mani;

plan tests => scalar @templates;

my $templater = Squirrel::Template->new
   (
    charset => "utf-8",
    utf8 => 1,
    template_dir => "site/templates",
   );
for my $file (@templates) {
  my ($p, $message) = $templater->parse_file($file);
  if ($p) {
    my @errors = $templater->errors;
    ok(!@errors, "check $file for template errors");
    diag("$_->[3]:$_->[2]: $_->[4]") for @errors;
    $templater->clear_errors;
  }
  else {
    fail("check $file for template errors");
    diag($message);
  }
}
