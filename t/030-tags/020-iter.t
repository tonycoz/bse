#!perl -w
use strict;
use Test::More tests => 3;
use BSE::Cfg;
use Squirrel::Template;

use_ok("BSE::Util::Iterate");

my $cfg = BSE::Cfg->new(path => "t/tags/");

my @firsts =
  (
   { name => "one", id => 3 },
   { name => "two", id => 1 },
   { name => "three", id => 2 },
  );

my @ids = map $_->{id}, @firsts;
my %ids = map { $_->{id} => $_ } @firsts;

my $it = BSE::Util::Iterate->new(cfg => $cfg);
my %acts =
  (
   BSE::Util::Tags->static(undef, $cfg),
   pi => "3.14159265",
   large => 1234567890,
   $it->make
   (
    single => "first",
    plural => "firsts",
    data => \@firsts,
   ),
   $it->make
   (
    single => "load",
    plural => "loads",
    data => \@ids,
    fetch => [ \&fetcher, \%ids ],
   ),
  );

template_test("simple iter", <<IN, <<OUT, \%acts);
<:iterator begin firsts
:><:first id:>: <:first name:>
  index: <:first_index:>
  number: <:first_number:>
  first: <:ifFirstFirst:>Y<:or:>N<:eif:>
  last: <:ifLastFirst:>Y<:or:>N<:eif:>
  prev name: <:previous_first name:>
  next name: <:next_first name:>
<:iterator end firsts:>
IN
3: one
  index: 0
  number: 1
  first: Y
  last: N
  prev name: 
  next name: two
1: two
  index: 1
  number: 2
  first: N
  last: N
  prev name: one
  next name: three
2: three
  index: 2
  number: 3
  first: N
  last: Y
  prev name: two
  next name: 

OUT

template_test("fetch iter", <<IN, <<OUT, \%acts);
<:iterator begin loads
:><:load id:>: <:load name:>
  index: <:load_index:>
  number: <:load_number:>
  first: <:ifFirstLoad:>Y<:or:>N<:eif:>
  last: <:ifLastLoad:>Y<:or:>N<:eif:>
  ifPrev: <:ifPreviousLoad:>Y<:or:>N<:eif:>
  ifNext: <:ifNextLoad:>Y<:or:>N<:eif:>
  prev name: <:previous_load name:>
  next name: <:next_load name:>
<:iterator end loads:>
IN
3: one
  index: 0
  number: 1
  first: Y
  last: N
  ifPrev: N
  ifNext: Y
  prev name: 
  next name: two
1: two
  index: 1
  number: 2
  first: N
  last: N
  ifPrev: Y
  ifNext: Y
  prev name: one
  next name: three
2: three
  index: 2
  number: 3
  first: N
  last: Y
  ifPrev: Y
  ifNext: N
  prev name: two
  next name: 

OUT

sub fetcher {
  my ($ids, $id) = @_;

  return $ids->{$id};
}

sub template_test {
  my ($note, $in, $out, $acts) = @_;

  my $templater = Squirrel::Template->new;
  my $result = $templater->replace_template($in, $acts);
  return is($result, $out, $note);
}
