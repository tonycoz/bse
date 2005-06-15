#!perl -w
use strict;
use BSE::Test ();
use Test::More tests=>67;
use File::Spec;
use FindBin;
my $cgidir = File::Spec->catdir(BSE::Test::base_dir, 'cgi-bin');
ok(chdir $cgidir, "switch to CGI directory");
push @INC, 'modules';
require BSE::Cfg;
my $cfg = BSE::Cfg->new;
# create some articles to test with
require Articles;
require BSE::Util::SQL;
BSE::Util::SQL->import(qw/sql_datetime/);
sub template_test($$$$);

my $parent = add_article(title=>'Parent', body=>'parent article',
			lastModified => '2004-09-23 06:00:00');
ok($parent, "create section");
my @kids;
for my $name ('One', 'Two', 'Three') {
  my $kid = add_article(title => $name, parentid => $parent->{id}, 
			body => "b[$name]");
  ok($kid, "creating kid $name");
  push(@kids, $kid);
}

# make parent a step child of itself
require BSE::Admin::StepParents;
BSE::Admin::StepParents->add($parent, $parent);

my $top = Articles->getByPkey(1);
ok($top, "grabbing Home page");

template_test "children_of", $top, <<TEMPLATE, <<EXPECTED;
<:iterator begin children_of $parent->{id}:><:
ofchild title:>
<:iterator end children_of:>
TEMPLATE
Three
Two
One

EXPECTED

template_test "allkids_of", $top, <<TEMPLATE, <<EXPECTED;
<:iterator begin allkids_of $parent->{id}:><:
ofallkid title:>
<:iterator end allkids_of:>
TEMPLATE
Parent
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
Three
Two
One

EXPECTED

template_test "embed children", $top, <<TEMPLATE, <<EXPECTED;
<:embed $parent->{id} test/children.tmpl:>
TEMPLATE
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
<:capitalize "'one day, but don't', 'we know'":>
TEMPLATE
abc123 xyz
ABC123 XYZ
abC123 XYZ
ABc123 xyz
Alpha Beta Gamma
'One Day, But Don't', 'We Know'
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

template_test "quotedreplace", $parent, <<'TEMPLATE', <<EXPECTED;
<:date "%FT%T%z" article lastModified:>
<meta name="DC.title" content="<:article title:>" />
<meta name="DC.date" content="<:replace [date "%FT%T%z" article lastModified] "(\d\d)$" ":$1":>" />
<meta name="DC.format" content="<:cfg site format "text/html":>" />
TEMPLATE
2004-09-23T06:00:00+1000
<meta name="DC.title" content="Parent" />
<meta name="DC.date" content="2004-09-23T06:00:00+10:00" />
<meta name="DC.format" content="text/html" />
EXPECTED

BSE::Admin::StepParents->del($parent, $parent);
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
     lastModifiedBy=>'t20gen', created=>sql_datetime(time),
     createdBy=>'t20gen', author=>'', pageTitle=>'',
    );
  for my $key (%defaults) {
    unless (exists $parms{$key}) {
      $parms{$key} = $defaults{$key};
    }
  }
  $parms{displayOrder} = $display_order;
  my @artcols = Article->columns;
  my $article = Articles->add(@parms{@artcols[1..$#artcols]});
  # use consistent links to ensure that the links remain consistent, even 
  # if they are incorrect
  $article->{link} = "/a/$display_order.html";
  $article->{admin} = "/cgi-bin/admin/admin.pl?id=$article->{id}";
  $article->save;
  $display_order += 100;

  $article;
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
