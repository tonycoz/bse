#!perl -w
use strict;
use BSE::Test ();
use Test::More tests=>80;
use File::Spec;
use FindBin;
BEGIN {
  my $cgidir = File::Spec->catdir(BSE::Test::base_dir, 'cgi-bin');
  ok(chdir $cgidir, "switch to CGI directory");
  push @INC, 'modules';
}
use BSE::API qw(bse_init bse_cfg bse_make_catalog bse_make_product);

bse_init(".");

my $cfg = bse_cfg();
require BSE::Util::SQL;
use DevHelp::Date qw(dh_strftime_sql_datetime);

BSE::DB->init($cfg);

BSE::Util::SQL->import(qw/sql_datetime/);
sub template_test($$$$);

my $parent = add_catalog
  (
   title=>'Test catalog', 
   body=>'test catalog',
   parentid => 3,
   lastModified => '2004-09-23 06:00:00',
   threshold => 2,
  );
ok($parent, "create parent catalog");
my @kids;
for my $name ('One', 'Two', 'Three') {
  my $kid = add_catalog(title => $name, parentid => $parent->{id}, 
			body => "b[$name]");
  ok($kid, "creating kid catalog $name");
  push(@kids, $kid);
}

my $stepkid = add_catalog(title=>'step kid', parentid=>3);
ok($stepkid, "adding step catalog");
my $stepprod = add_product(title=>'Delta', parentid=>$stepkid->{id},
			   retailPrice=>400);
ok($stepprod, "adding step product");

my %prices = ( Alpha => 100, Beta => 200, Gamma => 300 );
my @prods;
for my $name (qw(Alpha Beta Gamma)) {
  my $prod = add_product(title=>$name, retailPrice => $prices{$name},
			 parentid => $parent->{id});
  ok($prod, "creating kid product $name");
  push @prods, $prod;
}

require BSE::Admin::StepParents;
BSE::Admin::StepParents->add($parent, $stepkid);
sleep(2); # make sure they get a new displayOrder
BSE::Admin::StepParents->add($parent, $stepprod);

my $top = Articles->getByPkey(1);
ok($top, "grabbing Home page");

template_test "children_of", $top, <<TEMPLATE, <<EXPECTED;
<:iterator begin children_of $parent->{id}:><:
ofchild title:>
<:iterator end children_of:>
TEMPLATE
Gamma
Beta
Alpha
Three
Two
One

EXPECTED

template_test "allkids_of", $top, <<TEMPLATE, <<EXPECTED;
<:iterator begin allkids_of $parent->{id}:><:
ofallkid title:>
<:iterator end allkids_of:>
TEMPLATE
Delta
step kid
Gamma
Beta
Alpha
Three
Two
One

EXPECTED

my @kidids = map $_->{id}, @kids;
template_test "inlines", $top, <<TEMPLATE, <<EXPECTED;
<:iterator begin inlines @kidids:><:
inline title:><:iterator end inlines:>
TEMPLATE
OneTwoThree
EXPECTED

template_test "ifancestor positive", $kids[0], <<TEMPLATE, <<EXPECTED;
<:ifAncestor $parent->{id}:>Yes<:or:>No<:eif:>
TEMPLATE
Yes
EXPECTED

template_test "ifancestor equal", $kids[0], <<TEMPLATE, <<EXPECTED;
<:ifAncestor $kids[0]{id}:>Yes<:or:>No<:eif:>
TEMPLATE
Yes
EXPECTED

template_test "ifancestor negative", $kids[0], <<TEMPLATE, <<EXPECTED;
<:ifAncestor $kids[1]{id}:>Yes<:or:>No<:eif:>
TEMPLATE
No
EXPECTED

template_test "children", $parent, <<TEMPLATE, <<EXPECTED;
<:iterator begin children:><:
child title:>
<:iterator end children:>
TEMPLATE
Gamma
Beta
Alpha
Three
Two
One

EXPECTED

template_test "embed children", $top, <<TEMPLATE, <<EXPECTED;
<:embed $parent->{id} test/children.tmpl:>
TEMPLATE
Gamma
Beta
Alpha
Three
Two
One


EXPECTED

# test some of the newer basic tags
template_test "add", $top, <<TEMPLATE, <<EXPECTED;
<:add 3 4:>
<:add 3 4 5:>
<:add 3 [add 4 5]:>
TEMPLATE
7
12
12
EXPECTED

template_test "concatenate", $top, <<TEMPLATE, <<EXPECTED;
<:concatenate one two:>
<:concatenate one "two " three:>
<:concatenate one [concatenate "two " three]:>
<:concatenate [concatenate "one" [concatenate "two" "three"]]:>
TEMPLATE
onetwo
onetwo three
onetwo three
onetwothree
EXPECTED

template_test "match", $top, <<'TEMPLATE', <<EXPECTED;
<:match "abc123" "(\d+)":>
<:match "abc 123" "(\w+)\s+(\w+)" "$2$1":>
<:match "abc 123" "(\w+)X(\w+)" "$2$1":>
<:match "abc 123" "(\w+)X(\w+)" "$2$1" "default":>
TEMPLATE
123
123abc

default
EXPECTED

template_test "replace", $top, <<'TEMPLATE', <<EXPECTED;
<:replace "abc123" "(\d+)" "XXX" :>
<:replace "!!abc 123!!" "(\w+)\s+(\w+)" "$2$1":>
<:replace "abc 123" "(\w+)" "XXX" g:>
<:replace "abc 123" "X" "$1" :>
<:replace "abc
123
xyz" "\n" "\\n" g:>
TEMPLATE
abcXXX
!!123abc!!
XXX XXX
abc 123
abc\\n123\\nxyz
EXPECTED

template_test "cases", $top, <<'TEMPLATE', <<EXPECTED;
<:lc "AbC123 XYZ":>
<:uc "aBc123 xyz":>
<:lcfirst "AbC123 XYZ":>
<:ucfirst "aBc123 xyz":>
<:capitalize "alpha beta gamma":>
TEMPLATE
abc123 xyz
ABC123 XYZ
abC123 XYZ
ABc123 xyz
Alpha Beta Gamma
EXPECTED

template_test "arithmetic", $top, <<'TEMPLATE', <<EXPECTED;
<:arithmetic 2+2:>
<:arithmetic 2+[add 1 1]:>
<:arithmetic d2:1.234+1.542:>
<:arithmetic 2+[add 1 2]+[undefinedtag x]+[add 1 1]+[undefinedtag2]:>
TEMPLATE
4
4
2.78
<:arithmetic 2+[add 1 2]+[undefinedtag x]+[add 1 1]+[undefinedtag2]:>
EXPECTED

template_test "nobodytext", $kids[0], <<'TEMPLATE', <<EXPECTED;
<:nobodytext article body:>
TEMPLATE
One
EXPECTED

{
  my $mod = dh_strftime_sql_datetime("%a %d/%m/%Y", $parent->lastModified);
  template_test "date", $parent, <<'TEMPLATE', <<EXPECTED;
<:date "%a %d/%m/%Y" article lastModified:>
TEMPLATE
$mod
EXPECTED
}

template_test "strepeats", $parent, <<'TEMPLATE', <<EXPECTED;
<:iterator begin strepeats [arithmetic 1+1]:><:strepeat index:> <:strepeat value:>
<:iterator end strepeats:>
TEMPLATE
0 1
1 2

EXPECTED

template_test "strepeats2", $parent, <<'TEMPLATE', <<EXPECTED;
<:iterator begin strepeats [arithmetic 1+1] 5:><:strepeat index:> <:strepeat value:>
<:iterator end strepeats:>
TEMPLATE
0 2
1 3
2 4
3 5

EXPECTED

template_test "ifUnderThreshold parent allcats", $parent, <<TEMPLATE, <<EXPECTED;
<:ifUnderThreshold allcats:>1<:or:>0<:eif:>
TEMPLATE
0
EXPECTED

template_test "ifUnderThreshold parent allprods", $parent, <<TEMPLATE, <<EXPECTED;
<:ifUnderThreshold allprods:>1<:or:>0<:eif:>
TEMPLATE
0
EXPECTED

BSE::Admin::StepParents->del($parent, $stepkid);
BSE::Admin::StepParents->del($parent, $stepprod);
for my $kid (reverse @prods, $stepprod) {
  my $name = $kid->{title};
  $kid->remove($cfg);
  ok(1, "removing product $name");
}
for my $kid (reverse @kids, $stepkid) {
  my $name = $kid->{title};
  $kid->remove($cfg);
  ok(1, "removing kid $name");
}
$parent->remove($cfg);
ok(1, "removed parent");

sub add_article {
  my (%parms) = @_;

  my $article = bse_make_article(cfg => $cfg, parentid => -1, %parms);

  $article;
}

sub add_catalog {
  my (%parms) = @_;

  # this won't put the catalogs in the shop area, but that isn't needed 
  # for this case.
  return bse_make_catalog(cfg => $cfg, body => "", %parms);
}

sub add_product {
  my (%parms) = @_;

  return bse_make_product(cfg => $cfg, %parms);
}

sub template_test($$$$) {
  my ($tag, $article, $template, $expected) = @_;

  #diag "Template >$template<";
  my $gen = 
    eval {
      (my $filename = $article->{generator}) =~ s!::!/!g;
      $filename .= ".pm";
      require $filename;
      $article->{generator}->new(cfg => $cfg, top => $article);
    };
  ok($gen, "$tag: created generator $article->{generator}");
  diag $@ unless $gen;
  my $content;
 SKIP: {
    skip "$tag: couldn't make generator", 1 unless $gen;
    eval {
      $content =
	$gen->generate_low($template, $article, 'Articles', 0);
    };
    ok($content, "$tag: generate content");
    diag $@ unless $content;
  }
 SKIP: {
     skip "$tag: couldn't gen content", 1 unless $content;
     is($content, $expected, "$tag: comparing");
   }
}
