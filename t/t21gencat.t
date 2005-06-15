#!perl -w
use strict;
use BSE::Test ();
use Test::More tests=>69;
use File::Spec;
use FindBin;
my $cgidir = File::Spec->catdir(BSE::Test::base_dir, 'cgi-bin');
ok(chdir $cgidir, "switch to CGI directory");
push @INC, 'modules';
require BSE::Cfg;
my $cfg = BSE::Cfg->new;
# create some articles to test with
require Articles;
require Products;
require BSE::Util::SQL;
BSE::Util::SQL->import(qw/sql_datetime/);
sub template_test($$$$);

my $parent = add_catalog(title=>'Test catalog', body=>'test catalog',
			 parentid => 3,
			 lastModified => '2004-09-23 06:00:00');
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
step kid
Delta
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
<:arithmetic 2+3+[undefinedtag x]+2+[undefinedtag2]:>
EXPECTED

template_test "nobodytext", $kids[0], <<'TEMPLATE', <<EXPECTED;
<:nobodytext article body:>
TEMPLATE
One
EXPECTED

template_test "date", $parent, <<'TEMPLATE', <<EXPECTED;
<:date "%a %d/%m/%Y" article lastModified:>
TEMPLATE
Thu 23/09/2004
EXPECTED

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

BSE::Admin::StepParents->del($parent, $stepkid);
BSE::Admin::StepParents->del($parent, $stepprod);
for my $kid (reverse @kids) {
  my $name = $kid->{title};
  $kid->remove();
  ok(1, "removing kid $name");
}
$parent->remove();
ok(1, "removed parent");

my $display_order;
sub add_article {
  my (%parms) = @_;
  $display_order ||= 1000;
  my %defaults = 
    (
     parentid=>-1, displayOrder => 1000, title=>'Test Parent',
     titleImage => '', body=>'Test parent b[body]',
     thumbImage => '', thumbWidth => 0, thumbHeight => 0,
     imagePos => 'tr', release=>sql_datetime(time-86400), expire=>'2999-12-31',
     keyword=>'', template=>'common/default.tmpl', link=>'', admin=>'',
     threshold => 5, summaryLength => 100, generator=>'Generate::Article',
     level => 1, listed=>1, lastModified => sql_datetime(time), flags=>'',
     lastModifiedBy=>'t21gencat', created=>sql_datetime(time),
     createdBy=>'t21gencat', author=>'', pageTitle=>'',
    );
  for my $key (%defaults) {
    unless (exists $parms{$key}) {
      $parms{$key} = $defaults{$key};
    }
  }

  my $sing_type = $parms{_single} || 'Article';
  my $agg_type = $parms{_aggregate} || 'Articles';
  $parms{displayOrder} = $display_order;
  my @artcols = $sing_type->columns;
  my $article = $agg_type->add(@parms{@artcols[1..$#artcols]});
  # use consistent links to ensure that the links remain consistent, even 
  # if they are incorrect
  $article->{link} = "/a/$display_order.html";
  $article->{admin} = "/cgi-bin/admin/admin.pl?id=$article->{id}";
  $article->save;
  $display_order += 100;

  $article;
}

sub add_catalog {
  my (%parms) = @_;

  # this won't put the catalogs in the shop area, but that isn't needed 
  # for this case.
  return add_article(template=>'catalog.tmpl', 
		     generator=>'Generate::Catalog', 
		     %parms);
}

sub add_product {
  my (%parms) = @_;

  # this won't put the catalogs in the shop area, but that isn't needed 
  # for this case.
  return add_article(template=>'shopitem.tmpl', 
		     generator=>'Generate::Product', 
		     _single => 'Product',
		     _aggregate => 'Products',
		     summary => $parms{title} || '',
		     leadTime=> 0,
		     gst => int($parms{retailPrice} / 11),
		     options => '',
		     subscription_id => -1,
		     subscription_period => 0,
		     subscription_usage => 3,
		     subscription_required => -1,
		     %parms);
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
