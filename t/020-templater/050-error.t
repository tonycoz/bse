#!perl -w
use strict;

# error handling tests
use Squirrel::Template;
use Test::More;
use Carp qw(confess);
use Data::Dumper;

my @tests =
  (
   {
    name => "missing : in ?:",
    template => "<:= foo ? bar :>",
    errors =>
    [
     [ error => '', 1, 'test.tmpl', "Expected : for ? : operator but found eof" ],
    ],
    result => q/* Expected : for ? : operator but found eof */,
   },
   {
    name => "unrecognized junk after expr",
    template => "<:= foo ; :>",
    errors =>
    [
     [ error => '', 1, 'test.tmpl', "Expected eof but found op;" ],
    ],
    result => q/* Expected eof but found op; */,
   },
   {
    name => "ranges chained",
    template => "<:= [ 1...3...4 ] :>",
    errors =>
    [
     [ error => '', 1, 'test.tmpl', "Can't use a range as the start of a range" ],
    ],
    result => q/* Can't use a range as the start of a range */,
   },
   {
    name => "name.junk",
    template => "<:= name.; :>",
    errors =>
    [
     [ error => '', 1, 'test.tmpl', q(Expected a method name or $var after '.' but found ;) ],
    ],
    result => q/* Expected a method name or $var after '.' but found ; */,
   },
   {
    name => "name.\$junk",
    template => "<:= name.\$; :>",
    errors =>
    [
     [ error => '', 1, 'test.tmpl', "Expected an identifier after .\$ but found ;" ],
    ],
    result => q/* Expected an identifier after .$ but found ; */,
   },
   {
    name => "unterminated list",
    template => "<:= [ 1 :>",
    errors =>
    [
     [ error => '', 1, 'test.tmpl', "Expected list end ']' but got eof" ],
    ],
    result => q/* Expected list end ']' but got eof */,
   },
   {
    name => "unterminated subscript",
    template => "<:= name[1 :>",
    errors =>
    [
     [ error => '', 1, 'test.tmpl', "Expected closing ']' but got eof" ],
    ],
    result => q/* Expected closing ']' but got eof */,
   },
  );

plan tests => 3 * scalar(@tests);

my %acts = ();

my %vars = ();

# the following ensures the code isolates evals from __DIE__handlers
$SIG{__DIE__} = sub { confess @_ };

for my $test (@tests) {
  my ($name, $template, $want_errors, $want_result) =
    @$test{qw/name template errors result/};

  my $t = Squirrel::Template->new;
  my $result;
  my $good = eval {
    $result = $t->replace_template($template, \%acts, undef, 'test.tmpl', \%vars);
    1;
  };
  ok($good, "$name: compile and run template");
  is($result, $want_result, "$name: expected template result");
  is_deeply([ $t->errors ], $want_errors, "$name: expected errors")
    or note Dumper([$t->errors]);
}
