#!perl -w
use strict;
use BSE::Test ();
use Test::More tests=>31;
use File::Spec;
use FindBin;
my $cgidir = File::Spec->catdir(BSE::Test::base_dir, 'cgi-bin');
ok(chdir $cgidir, "switch to CGI directory");
push @INC, 'modules';
# create some articles to test with
require Articles;
require BSE::Util::SQL;
BSE::Util::SQL->import(qw/sql_datetime/);
sub template_test($$$$);

my $parent = add_article(title=>'Parent', body=>'parent article');
ok($parent, "create section");
my @kids;
for my $name ('One', 'Two', 'Three') {
  my $kid = add_article(title => $name, parentid => $parent->{id}, 
			body => "b[$name]");
  ok($kid, "creating kid $name");
  push(@kids, $kid);
}

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
     level => 1, listed=>1, lastModified => sql_datetime(time),
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
      $article->{generator}->new();
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
