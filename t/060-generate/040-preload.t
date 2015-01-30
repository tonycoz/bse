#!perl -w
use strict;
use BSE::Test;
use Cwd;
use Test::More;
my $start_dir;
BEGIN {
  $start_dir = getcwd();
  my $cgidir = File::Spec->catdir(BSE::Test::base_dir, 'cgi-bin');
  ok(chdir $cgidir, "switch to CGI directory");
  push @INC, 'modules';
}
use BSE::API qw(bse_init bse_cfg);
use BSE::Template;
use BSE::Variables;
use BSE::Request::Test;

bse_init(".");

my $cfg = bse_cfg();

my %params;
$params{p} = 11;
my $r = BSE::Request::Test->new
  (
   params => \%params,
  );

my $t = BSE::Template->templater($cfg);
my $vars = 
  {
   bse => BSE::Variables->dyn_variables
   (
    request => $r,
   ),
  };

template_test(<<'IN', <<'EXPECT', "page_list");
<:.set items = [ 1 .. 200 ] -:>
<:.set p = bse.paged(items, { pp: 5 }) -:>
<:= p.items.join(" ") :>
<:.call "page_list", base:"/", pages: p :>
IN
51 52 53 54 55

<div class="pagelist">
Page 11 of 40
<a href="/?p=1&amp;pp=5">&lt;&lt</a>
<a href="/?p=10&amp;pp=5">&lt;</a>

<a href="/?p=1&amp;pp=5">1</a>

<a href="/?p=2&amp;pp=5">2</a>

<a href="/?p=3&amp;pp=5">3</a>

<a href="/?p=4&amp;pp=5">4</a>

<a href="/?p=5&amp;pp=5">5</a>

<a href="/?p=6&amp;pp=5">6</a>

<a href="/?p=7&amp;pp=5">7</a>

<a href="/?p=8&amp;pp=5">8</a>

<a href="/?p=9&amp;pp=5">9</a>

<a href="/?p=10&amp;pp=5">10</a>

<span>11</span>

<a href="/?p=12&amp;pp=5">12</a>

<span>...</span>

<a href="/?p=33&amp;pp=5">33</a>

<a href="/?p=34&amp;pp=5">34</a>

<a href="/?p=35&amp;pp=5">35</a>

<a href="/?p=36&amp;pp=5">36</a>

<a href="/?p=37&amp;pp=5">37</a>

<a href="/?p=38&amp;pp=5">38</a>

<a href="/?p=39&amp;pp=5">39</a>

<a href="/?p=40&amp;pp=5">40</a>

<a href="/?p=12&amp;pp=5">&gt;</a>
<a href="/?p=40&amp;pp=5">&gt;&gt</a>
</div>
EXPECT

done_testing();

sub template_test {
  my ($in, $expect, $note) = @_;

  my $result = $t->replace_template($in, {}, undef, undef, $vars);
  my $b = Test::More->builder;
  return $b->is_eq($result, $expect, $note);
}
