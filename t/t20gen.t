#!perl -w
use strict;
use BSE::Test ();
use Test::More tests=>141;
use File::Spec;
use FindBin;
my $cgidir = File::Spec->catdir(BSE::Test::base_dir, 'cgi-bin');
ok(chdir $cgidir, "switch to CGI directory");
push @INC, 'modules';
require BSE::Cfg;
my $cfg = BSE::Cfg->new;
use BSE::DB;
BSE::DB->init($cfg);
# create some articles to test with
require Articles;
require BSE::Util::SQL;
BSE::Util::SQL->import(qw/sql_datetime/);
sub template_test($$$$);
sub dyn_template_test($$$$);

my $parent = add_article
  (
   title=>'Parent', 
   body=>'parent article doclink[shop|foo]',
   lastModified => '2004-09-23 06:00:00',
   threshold => 2,
  );
ok($parent, "create section");
my @kids;
for my $name ('One', 'Two', 'Three') {
  my $kid = add_article
    (
     title => $name, parentid => $parent->{id}, 
     body => "b[$name] - alpha, beta, gamma, delta, epsilon",
     summaryLength => 35,
    );
  ok($kid, "creating kid $name");
  push(@kids, $kid);
}

my $grandkid = add_article
  (
   parentid => $kids[1]{id},
   title => "Grandkid",
   body => "grandkid",
  );

my $base_securl = $cfg->entryVar("site", "secureurl");

# make parent a step child of itself
require BSE::Admin::StepParents;
BSE::Admin::StepParents->add($parent, $parent);

is($parent->section->{id}, $parent->{id}, "parent should be it's own section");
is($kids[0]->section->{id}, $parent->{id}, "kids section should be the parent");

my $top = Articles->getByPkey(1);
ok($top, "grabbing Home page");

template_test "cfg", $top, <<TEMPLATE, <<EXPECTED;
<:cfg "no such section" somekey "default / value":>
TEMPLATE
default / value
EXPECTED

template_test "formats", $top, <<TEMPLATE, <<EXPECTED;
<:arithmetic 10 |%05d:>
TEMPLATE
00010
EXPECTED

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

template_test "allkids_of filtered", $top, <<TEMPLATE, <<EXPECTED;
<:iterator begin allkids_of $parent->{id} filter: [title] =~ /o/i :><:
ofallkid title:>
<:iterator end allkids_of:>
TEMPLATE
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
<:capitalize "IBM stock soars":>
TEMPLATE
abc123 xyz
ABC123 XYZ
abC123 XYZ
ABc123 xyz
Alpha Beta Gamma
'One Day, But Don't', 'We Know'
Ibm Stock Soars
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
One - alpha, beta, gamma, delta, epsilon
EXPECTED

template_test "date", $parent, <<'TEMPLATE', <<EXPECTED;
<:date "%a %d/%m/%Y" article lastModified:>
TEMPLATE
Thu 23/09/2004
EXPECTED

use POSIX;
template_test "today", $parent, <<'TEMPLATE', strftime("%Y-%m-%d %d-%b-%Y\n", localtime);
<:today "%Y-%m-%d":> <:today:>
TEMPLATE

SKIP:
{
  eval {
    require Date::Format;
  };

  $@
    and skip("No Date::Format", 3);

  my $today = Date::Format::strftime("%a %o %B %Y", [ localtime ]);
  template_test "date/today w/Date::Format", $parent, <<'TEMPLATE', <<EXPECTED;
<:date "%A %o %B %Y" article lastModified:> <:today "%a %o %B %Y":>
TEMPLATE
Thursday 23rd September 2004 $today
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

template_test "report", $parent, <<'TEMPLATE', <<EXPECTED;
<:report bse_test test/testrep 2:>
<:report bse_test test/testrep [article id]:>
TEMPLATE
Report: Test report
id title
2 [index subsection]
Report: Test report
id title
$parent->{id} Parent
EXPECTED

template_test "body", $parent, <<'TEMPLATE', <<EXPECTED;
<:body:>
TEMPLATE
<p>parent article <a href="$base_securl/shop/index.html" title="The Shop" class="doclink">foo</a></p>
EXPECTED

# not actually generation tests, but chekcs that the is_step_ancestor works
ok($kids[0]->is_step_ancestor($parent->{id}),
   "is_step_ancestor - check normal parent");
ok($parent->is_step_ancestor($parent->{id}),
   "is_step_ancestor - check step parent");
ok(!$parent->is_step_ancestor($kids[0]),
   "is_step_ancestor - failure check");

# and test the static tag
template_test "ifStepAncestor 1", $parent, <<'TEMPLATE', <<EXPECTED;
<:ifStepAncestor article:>Good<:or:>bad<:eif:>
<:ifStepAncestor 3:>Bad<:or:>Good<:eif:>
TEMPLATE
Good
Good
EXPECTED

template_test "ifStepAncestor 2", $kids[0], <<TEMPLATE, <<EXPECTED;
<:ifStepAncestor parent:>Good<:or:>bad<:eif:>
<:ifStepAncestor article:>Good<:or:>Bad<:eif:>
<:ifStepAncestor $kids[2]{id}:>Bad<:or:>Good<:eif:>
TEMPLATE
Good
Good
Good
EXPECTED

template_test "ifAnd dynamic cfg ajax", $parent, <<TEMPLATE, <<EXPECTED;
<:ifAnd [ifDynamic] [cfg basic ajax]:>1<:or:>0<:eif:>
TEMPLATE
0
EXPECTED

template_test "replace complex re", $parent, <<'TEMPLATE', <<EXPECTED;
<:replace "test&amp;test 01234567890123456789" ((?:&[^;]*;|[^&]){16}).* $1...:>
TEMPLATE
test&amp;test 012345...
EXPECTED

template_test "summary", $kids[0], <<'TEMPLATE', <<EXPECTED;
<:summary article:>
<:summary article 14:>
TEMPLATE
One - alpha, beta, gamma, delta,...
One - alpha,...
EXPECTED

template_test "ifUnderThreshold parent children", $parent, <<'TEMPLATE', <<EXPECTED;
<:ifUnderThreshold:>1<:or:>0<:eif:>
<:ifUnderThreshold children:>1<:or:>0<:eif:>
TEMPLATE
0
0
EXPECTED

template_test "ifUnderThreshold parent allkids", $parent, <<'TEMPLATE', <<EXPECTED;
<:ifUnderThreshold allkids:>1<:or:>0<:eif:>
TEMPLATE
0
EXPECTED

template_test "ifUnderThreshold parent stepkids", $parent, <<'TEMPLATE', <<EXPECTED;
<:ifUnderThreshold stepkids:>1<:or:>0<:eif:>
TEMPLATE
1
EXPECTED

template_test "ifUnderThreshold child children", $kids[0], <<'TEMPLATE', <<EXPECTED;
<:ifUnderThreshold:>1<:or:>0<:eif:>
<:ifUnderThreshold children:>1<:or:>0<:eif:>
TEMPLATE
1
1
EXPECTED

template_test "ifUnderThreshold child allkids", $kids[0], <<'TEMPLATE', <<EXPECTED;
<:ifUnderThreshold allkids:>1<:or:>0<:eif:>
TEMPLATE
1
EXPECTED

template_test "ifUnderThreshold child stepkids", $kids[0], <<'TEMPLATE', <<EXPECTED;
<:ifUnderThreshold stepkids:>1<:or:>0<:eif:>
TEMPLATE
1
EXPECTED

template_test "noreplace undefined", $parent, <<'TEMPLATE', <<'EXPECTED';
<:switch:><:case Dynallkids_of2 dynofallkid filter: [listed] != 2 :><:if Or [ifAncestor dynofallkid] [ifEq [cgi catid] [dynofallkid id]]:>
contentA
  <:iterator begin dynallkids_of2 dynofallkid filter: [listed] != 2 && [generator] =~ /Catalog/ :>
contentB
<:ifEq [dynarticle id] [dynofallkid2 id]:> focus<:or:><:eif:>
<:ifAncestor dynofallkid2:> hilite<:or:><:eif:>
<:ifFirstDynofallkid2:> first<:or:><:eif:>
<:ifLastDynofallkid2:> last<:or:><:eif:>
<:ifDynallkids_of3 dynofallkid2 filter: [listed] != 2 :> parent<:or:><:eif:>
<:ifDynofallkid2 titleAlias:><:dynofallkid2 titleAlias:><:or:><:dynofallkid2 title:><:eif:>
<:iterator separator dynallkids_of2:>
<:iterator end dynallkids_of2:>
<:or Or:><:eif Or:><:endswitch:>
TEMPLATE
<:switch:><:case Dynallkids_of2 dynofallkid filter: [listed] != 2 :><:if Or [ifAncestor dynofallkid] [ifEq [cgi catid] [dynofallkid id]]:>
contentA
  <:iterator begin dynallkids_of2 dynofallkid filter: [listed] != 2 && [generator] =~ /Catalog/ :>
contentB
<:ifEq [dynarticle id] [dynofallkid2 id]:> focus<:or:><:eif:>
<:ifAncestor dynofallkid2:> hilite<:or:><:eif:>
<:ifFirstDynofallkid2:> first<:or:><:eif:>
<:ifLastDynofallkid2:> last<:or:><:eif:>
<:ifDynallkids_of3 dynofallkid2 filter: [listed] != 2 :> parent<:or:><:eif:>
<:ifDynofallkid2 titleAlias:><:dynofallkid2 titleAlias:><:or:><:dynofallkid2 title:><:eif:>
<:iterator separator dynallkids_of2:>
<:iterator end dynallkids_of2:>
<:or Or:><:eif Or:><:endswitch:>
EXPECTED

############################################################
# dynamic stuff
require BSE::Dynamic::Article;
require BSE::Request::Test;
my $req = BSE::Request::Test->new(cfg => $cfg);
my $gen = BSE::Dynamic::Article->new($req);

dyn_template_test "dynallkidsof", $parent, <<TEMPLATE, <<EXPECTED;
<:iterator begin dynallkids_of $parent->{id} filter: [title] =~ /o/i :><:
dynofallkid title:> <:next_dynofallkid title:> <:previous_dynofallkid title:>
  next: <:ifNextDynofallkid:>Y<:or:>N<:eif:>
  previous: <:ifPreviousDynofallkid:>Y<:or:>N<:eif:>
<:iterator end dynallkids_of:>
TEMPLATE
Two One 
  next: Y
  previous: N
One  Two
  next: N
  previous: Y

EXPECTED

dyn_template_test "dynallkidsof nested", $parent, <<TEMPLATE, <<EXPECTED;
<:iterator begin dynallkids_of $parent->{id} filter: [title] =~ /o/i :><:
dynofallkid title:><:iterator begin dynallkids_of2 dynofallkid:>
  <:dynofallkid2 title:><:iterator end dynallkids_of2:>
<:iterator end dynallkids_of:>
TEMPLATE
Two
  Grandkid
One

EXPECTED

dyn_template_test "dynallkidsof nested filtered cond", $parent, <<TEMPLATE, <<EXPECTED;
<:iterator begin dynallkids_of dynarticle:><:dynofallkid title:><:if Dynallkids_of2 dynofallkid filter: [title] =~ /G/:><:iterator begin dynallkids_of2 dynofallkid filter: [title] =~ /G/:>
  <:dynofallkid2 title:><:iterator end dynallkids_of2:><:or Dynallkids_of2:>
  No G kids<:eif Dynallkids_of2:>
<:iterator end dynallkids_of:>
TEMPLATE
Parent
  No G kids
Three
  No G kids
Two
  Grandkid
One
  No G kids

EXPECTED

dyn_template_test "dynallkids_of move_dynofallkid", $parent, <<TEMPLATE, <<EXPECTED;
<:iterator begin dynallkids_of dynarticle:><:dynofallkid title:><:move_dynofallkid:>
<:iterator end dynallkids_of:>
TEMPLATE
Parent
Three
Two
One

EXPECTED

############################################################
# Cleanup

BSE::Admin::StepParents->del($parent, $parent);
$grandkid->remove($cfg);
for my $kid (reverse @kids) {
  my $name = $kid->{title};
  my $kidid = $kid->{id};
  $kid->remove($cfg);
  ok(1, "removing kid $name ($kidid)");
}
$parent->remove($cfg);
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
     cached_dynamic => 0, force_dynamic=>0, inherit_siteuser_rights => 1,
     metaDescription => '',  metaKeywords => '',
     summary => '', menu => '', titleAlias => '', linkAlias => '',
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
  $article->{link} = "/a/$article->{id}.html";
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

sub dyn_template_test($$$$) {
  my ($tag, $article, $template, $expected) = @_;

  #diag "Template >$template<";
  my $gen = 
    eval {
      my $gen_class = $article->{generator};
      $gen_class =~ s/.*\W//;
      $gen_class = "BSE::Dynamic::".$gen_class;
      (my $filename = $gen_class) =~ s!::!/!g;
      $filename .= ".pm";
      require $filename;
      $gen_class->new($req);
    };
  ok($gen, "$tag: created generator $article->{generator}");
  diag $@ unless $gen;

  # get the template - always regen it
  my $work_template = _generate_dyn_template($article, $template);

  my $result;
 SKIP: {
    skip "$tag: couldn't make generator", 1 unless $gen;
    eval {
      $result =
	$gen->generate($article, $work_template);
    };
    ok($result, "$tag: generate content");
    diag $@ unless $result;
  }
 SKIP: {
     skip "$tag: couldn't gen content", 1 unless $result;
     is($result->{content}, $expected, "$tag: comparing");
   }
}

sub _generate_dyn_template {
  my ($article, $template) = @_;

  my $articles = 'Articles';
  my $genname = $article->{generator};
  eval "use $genname";
  $@ && die $@;
  my $gen = $genname->new(articles=>$articles, cfg=>$cfg, top=>$article);

  return $gen->generate_low($template, $article, $articles, 0);
}
