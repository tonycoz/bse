#!perl -w
use strict;
use BSE::Test ();
use Test::More tests => 38;
use File::Spec;
use Carp qw(confess);

$SIG{__DIE__} = sub { confess @_ };

BEGIN {
  unshift @INC, File::Spec->catdir(BSE::Test::base_dir(), "cgi-bin", "modules");
}

use BSE::API ':all';

my $base_cgi = File::Spec->catdir(BSE::Test::base_dir(), "cgi-bin");
ok(bse_init($base_cgi),   "initialize api")
  or print "# failed to bse_init in $base_cgi\n";
my $cfg = bse_cfg;

# set up some test data
my $parent = bse_make_catalog(title => "Tags parent",
			      cfg => $cfg);
ok($parent, "make parent article");
my @kids;
my %kids;
for my $title ("A" .. "Z") {
  my $kid = bse_make_product
    (
     cfg => $cfg,
     title => $title,
     retailPrice => 0,
     parentid => $parent->id
    );
  push @kids, $kid;
  $kids{$title} = $kid;
}

{
  my %tags =
    (
     A => "Platform: iPad/iPad: iPad 1",
     B => "Platform: iPad/iPad: iPad 1",
     C => "Platform: iPad/iPad: iPad 2",
     D => "Platform: iPad/iPad: iPad 2",
     E => "Platform: iPad/iPad: iPad 2",
     F => "Platform: iPad/iPad: iPad 3",
     G => "Platform: iPod/iPod: Classic",
     H => "Platform: iPod/iPod: Classic",
     I => "Platform: iPod/iPod: Nano",
     J => "Platform: iPod/iPod: Nano",
     K => "Platform: iPod/iPod: 6th Gen",
     L => "Platform: iPod/iPod: 6th Gen",
     M => "Platform: iPhone/iPhone: 3G",
     N => "Platform: iPhone/iPhone: 3G",
     O => "Platform: iPhone/iPhone: 3GS",
     P => "Platform: iPhone/iPhone: 4",
     Q => "Platform: iPhone/iPhone: 4",
    );

  # set the tags
  my $all_set = 1;
  for my $title (keys %tags) {
    my $kid = $kids{$title} or die "No kid $title found";
    my $error;
    unless ($kid->set_tags([ split '/', $tags{$title} ], \$error)) {
      diag "Setting $title tags: $error\n";
      $all_set = 0;
    }
  }
  ok($all_set, "all kid tags set");
}

{
  my @tags = $kids[0]->tag_objects;
  my @ids = sort map $_->id, @tags;
  is_deeply([ sort $kids[0]->tag_ids ], \@ids, "check tag_ids works");
}

{
  my $tag_info = BSE::TB::Products->collection_with_tags
    (
     "all_visible_products",
     [ "iPod: Nano" ],
     { args => [ $parent->id ] },
    );
  my @expect = map $_->id, sort { $a->id <=> $b->id } @kids{"I", "J"};
  my @found = map $_->id, sort { $a->id <=> $b->id } @{$tag_info->{objects}};
  is_deeply(\@found, \@expect, "collection with tags on all_visible_products");
}

is_deeply([ map $_->title, $parent->children ],
	  [ reverse("A" .. "Z") ],
	  "check the childrent are in place");

{
  ok(!$parent->can("children_tags"), "non-optimized path");
  my $tagged = $parent->collection_with_tags
    (
     "children",
     [ "Platform: iPad" ]
    );
  ok($tagged, "collection_with_tags returned");
 SKIP:
  {
    ok($tagged->{objects}, "has objects")
      or skip("No objects", 1);
    is_deeply([ map $_->title, @{$tagged->{objects}} ],
	      [ reverse("A" .. "F") ],
	      "check we got the expected kids");
  }
 SKIP:
  {
    ok($tagged->{object_ids}, "has object_ids")
      or skip("No object_ids", 1);
    is_deeply($tagged->{object_ids},
	      [ map $_->id, @kids{reverse("A" .. "F")} ],
	      "check object_ids");
  }
 SKIP:
  {
    ok($tagged->{extratags}, "has extratags")
      or skip("No extratags", 1);
    is(join("/", sort map $_->name, @{$tagged->{extratags}}),
       "iPad: iPad 1/iPad: iPad 2/iPad: iPad 3",
       "check knowntags");
  }
  ok($tagged->{members}, "has members");
 SKIP:
  {
    ok($tagged->{counts}, "has counts")
      or skip("No counts", 1);
    is_deeply($tagged->{counts},
	      {
	       "iPad: iPad 1" => 2,
	       "iPad: iPad 2" => 3,
	       "iPad: iPad 3" => 1,
	      }, "check counts");
  }
}

{
  ok($parent->can("all_visible_product_tags"), "optimized path");
  my $tagged = $parent->collection_with_tags
    (
     "all_visible_products",
     [ "Platform: iPad" ]
    );
  ok($tagged, "collection_with_tags returned (all_visible_products)");
 SKIP:
  {
    ok($tagged->{objects}, "has objects")
      or skip("No objects", 1);
    is_deeply([ map $_->title, @{$tagged->{objects}} ],
	      [ reverse("A" .. "F") ],
	      "check we got the expected kids");
  }
 SKIP:
  {
    ok($tagged->{object_ids}, "has object_ids")
      or skip("No object_ids", 1);
    is_deeply($tagged->{object_ids},
	      [ map $_->id, @kids{reverse("A" .. "F")} ],
	      "check object_ids");
  }
 SKIP:
  {
    ok($tagged->{extratags}, "has extratags")
      or skip("No extratags", 1);
    is(join("/", sort map $_->name, @{$tagged->{extratags}}),
       "iPad: iPad 1/iPad: iPad 2/iPad: iPad 3",
       "check knowntags");
  }
  ok($tagged->{members}, "has members");
 SKIP:
  {
    ok($tagged->{counts}, "has counts")
      or skip("No counts", 1);
    is_deeply($tagged->{counts},
	      {
	       "iPad: iPad 1" => 2,
	       "iPad: iPad 2" => 3,
	       "iPad: iPad 3" => 1,
	      }, "check counts");
  }
}

{
  ok($parent->can("all_visible_product_tags"), "optimized path");
  my $tagged = $parent->collection_with_tags
    (
     "all_visible_products",
     [ "Platform: iPad" ],
     { noobjects => 1 }
    );
  ok($tagged, "collection_with_tags returned (all_visible_products, no objects)");
  ok(!$tagged->{objects}, "no objects");
 SKIP:
  {
    ok($tagged->{object_ids}, "has object_ids")
      or skip("No object_ids", 1);
    # they don't necessarily come back in order
    is_deeply([ sort @{$tagged->{object_ids}} ],
	      [ sort map $_->id, @kids{reverse("A" .. "F")} ],
	      "check object_ids");
  }
 SKIP:
  {
    ok($tagged->{extratags}, "has extratags")
      or skip("No extratags", 1);
    is(join("/", sort map $_->name, @{$tagged->{extratags}}),
       "iPad: iPad 1/iPad: iPad 2/iPad: iPad 3",
       "check knowntags");
  }
  ok($tagged->{members}, "has members");
 SKIP:
  {
    ok($tagged->{counts}, "has counts")
      or skip("No counts", 1);
    is_deeply($tagged->{counts},
	      {
	       "iPad: iPad 1" => 2,
	       "iPad: iPad 2" => 3,
	       "iPad: iPad 3" => 1,
	      }, "check counts");
  }
}

END {
  for my $kid (@kids) {
    $kid->remove($cfg);
  }
  $parent->remove($cfg) if $parent;
}
