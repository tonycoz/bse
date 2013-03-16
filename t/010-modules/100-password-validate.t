#!perl -w
use strict;
use Test::More;
use BSE::Util::PasswordValidate;
use Data::Dumper;

my @tests =
   (
    {
     name => "simple pass",
     args =>
     {
      password => "test",
      rules => {},
     },
    },
    {
     name => "length fail",
     result => 0,
     args =>
     {
      password => "test",
      rules =>
      {
       length => 5,
      },
     },
     errors =>
     [
      "msg:bse/util/password/length:4:5"
     ],
    },
    {
     name => "entropy fail",
     result => 0,
     args =>
     {
      password => "test",
      rules =>
      {
       entropy => 80,
      },
     },
     errors =>
     [
      "msg:bse/util/password/entropy:16:80:20"
     ],
    },
    # symbols
    {
     name => "symbols fail",
     result => 0,
     args =>
     {
      password => "test",
      rules =>
      {
       symbols => 1,
      },
     },
     errors =>
     [
      "msg:bse/util/password/symbols",
     ],
    },
    {
     name => "symbols success",
     result => 1,
     args =>
     {
      password => "alpha&beta",
      rules =>
      {
       symbols => 1,
      },
     },
    },

    # digits
    {
     name => "digits fail",
     result => 0,
     args =>
     {
      password => "test",
      rules =>
      {
       digits => 1,
      },
     },
     errors =>
     [
      "msg:bse/util/password/digits",
     ],
    },
    {
     name => "digits success",
     result => 1,
     args =>
     {
      password => "alpha5beta",
      rules =>
      {
       digits => 1,
      },
     },
    },

    # mixedcase
    {
     name => "mixedcase fail",
     result => 0,
     args =>
     {
      password => "test",
      rules =>
      {
       mixedcase => 1,
      },
     },
     errors =>
     [
      "msg:bse/util/password/mixedcase",
     ],
    },
    {
     name => "mixedcase success",
     result => 1,
     args =>
     {
      password => "Test",
      rules =>
      {
       mixedcase => 1,
      },
     },
    },

    # categories
    {
     name => "categories fail",
     result => 0,
     args =>
     {
      password => "test",
      rules =>
      {
       categories => 3,
      },
     },
     errors =>
     [
      "msg:bse/util/password/categories:1:3"
     ],
    },
    {
     name => "categories success",
     result => 1,
     args =>
     {
      password => "Test1",
      rules =>
      {
       categories => 3,
      },
     },
    },

    # notuser
    {
     name => "notuser fail",
     result => 0,
     args =>
     {
      password => "test",
      rules =>
      {
       notuser => 1,
      },
     },
     errors =>
     [
      "msg:bse/util/password/notuser",
     ],
    },
    {
     name => "notuser fail (case)",
     result => 0,
     args =>
     {
      password => "TEST",
      rules =>
      {
       notuser => 1,
      },
     },
     errors =>
     [
      "msg:bse/util/password/notuser",
     ],
    },
    {
     name => "notuser success",
     result => 1,
     args =>
     {
      password => "abcd",
      rules =>
      {
       notuser => 1,
      },
     },
    },

    # notu5er
    {
     name => "notu5er fail",
     result => 0,
     args =>
     {
      password => "te5t",
      rules =>
      {
       notu5er => 1,
      },
     },
     errors =>
     [
      "msg:bse/util/password/notu5er",
     ],
    },
    {
     name => "notu5er fail (case)",
     result => 0,
     args =>
     {
      password => "TE5T",
      rules =>
      {
       notu5er => 1,
      },
     },
     errors =>
     [
      "msg:bse/util/password/notu5er",
     ],
    },
    {
     name => "notu5er success",
     result => 1,
     args =>
     {
      password => "abcd",
      rules =>
      {
       notu5er => 1,
      },
     },
    },
   );

plan tests => 2 * @tests;

for my $test (@tests) {
  $test->{args}{other} ||= {};
  $test->{args}{username} ||= "testuser";
  exists $test->{result} or $test->{result} = 1;
  $test->{errors} ||= [];
  my $name = $test->{name};
  my @errors;
  my $result = BSE::Util::PasswordValidate->validate
    (
     %{$test->{args}},
     errors => \@errors,
    );
  note("$name => $result");
  note(Dumper(\@errors));
  ok($test->{result} ? $result : !$result, "$name: result");
  is_deeply(\@errors, $test->{errors}, "$name: check error messages");
}
