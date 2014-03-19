#!perl -w
use strict;
use BSE::Test qw(make_ua base_url);
use Test::More tests => 90;
use File::Spec;
use File::Slurp;
use Carp qw(confess);

$SIG{__DIE__} = sub { confess @_ };

BEGIN {
  unshift @INC, File::Spec->catdir(BSE::Test::base_dir(), "cgi-bin", "modules");
}

BEGIN { use_ok("BSE::API", ":all") }

my $ua = make_ua();

my $base_cgi = File::Spec->catdir(BSE::Test::base_dir(), "cgi-bin");
ok(bse_init($base_cgi),   "initialize api")
  or print "# failed to bse_init in $base_cgi\n";
my $cfg = bse_cfg();
ok($cfg, "we have a cfg object");

my $art = bse_make_article(cfg => $cfg,
			   title => "API test");
ok($art, "make a basic article");

my $child = bse_make_article(cfg => $cfg,
			     title => "API test child",
			     parentid => $art->id);
ok($child, "make a child article");

ok($child->is_descendant_of($art), "check decendant by object");
ok($child->is_descendant_of($art->id), "check decendant by id");

my $im1 = bse_add_image($cfg, $art, file => "t/data/t101.jpg");
ok($im1, "add an image, just a filename");

my $byindex = $art->image_by_index(1);
is($byindex->id, $im1->id, "check image_by_index()");

my $im2;
{
  open my $fh, "<", "t/data/t101.jpg"
    or die "Cannot open test image: $!\n";
  $im2 = bse_add_image($cfg, $art, fh => $fh, display_name => "t101.jpg");
  ok($im2, "add an image by fh");
}

# just set alt text
{
  my %errors;
  ok(bse_save_image($im1, alt => "Test", errors => \%errors),
     "update alt text");
  my $im = BSE::TB::Images->getByPkey($im1->id);
  ok($im, "found im1 independently");
  is($im->alt, "Test", "alt is set");
}

{ # change the image content (by name)
  my %errors;
  ok(bse_save_image($im1, file => "t/data/govhouse.jpg", errors => \%errors),
     "save new image content");
  is_deeply(\%errors, {}, "no errors");
  like($im1->src, qr(^/), "src should start with /, assuming no storage");
}

{ # change the image content (by fh)
  my %errors;
  open my $fh, "<", "t/data/govhouse.jpg"
    or die "Cannot open t/data/govhouse.jpg: $!";
  ok(bse_save_image($im2, fh => $fh, , display_name => "govhouse.jpg",
		    errors => \%errors),
     "save new image content (by fh)");
  is_deeply(\%errors, {}, "no errors");
  like($im2->src, qr(^/), "src should start with /, assuming no storage");
}

{
  # check we can retrieve the image
  my $src = base_url() . $im2->image_url;
  my $imres = $ua->get($src);
  open my $fh, "<", "t/data/govhouse.jpg"
    or die "Cannot open t/data/govhouse.jpg: $!";
  binmode $fh;
  my $orig = do { local $/; <$fh> };
  close $fh;
  ok($imres->is_success, "got some data");
  is($imres->decoded_content, $orig, "check it matches");
}

SKIP: {
  eval { require Imager; }
    or skip "No Imager", 2;
  # check thumbnailing
  my $thumb_url = base_url() . $im2->dynamic_thumb_url(geo => "editor");
  $thumb_url .= "&cache=0";
  print "# $thumb_url\n";
  my $thumb_res = $ua->get($thumb_url);
  ok($thumb_res->is_success, "successful fetch");
  like($thumb_res->content_type, qr(^image/[a-z]+$), "check content type");
  print "# ", $thumb_res->content_type, "\n";
}

{
  my $error;
  ok($art->set_tags([ "colour: red", "size: large" ], \$error),
     "set some tags should succeed");
  my $cat = BSE::TB::Articles->tag_category("colour");
  ok($cat, "get the 'colour' tag cat");
  my @orig_deps = $cat->deps;

  ok($cat->set_deps([], \$error), "empty deps list")
    or diag "setting deps empty: ", $error;

  ok($cat->set_deps([ "abc:", "def :", "efg: ", "alpha:beta" ], \$error),
     "set deps");
  is_deeply([$cat->deps],
	    [ "abc:", "alpha: beta", "def:", "efg:" ],
	    "check they were set");

  ok($cat->set_deps([ "abc:", "hij:" ], \$error),
     "set deps that add and remove to the list");

  is_deeply([$cat->deps],
	    [ "abc:", "hij:" ],
	    "check they were set");

  ok($cat->set_deps(\@orig_deps, \$error), "restore deps list")
    or diag "restoring deps: ", $error;
}

{ # adding a file
  { # this should fail, file isn't a handle
    my $file;
    ok(!eval { $file = $art->add_file
	     (
	      $cfg,
	      displayName => "test.txt",
	      file => "t/t000load.t",
	      store => 0,
	     ) }, "file must be a file handle");
    like($@, qr/file must be a file handle/, "check message");

    ok(!eval { $file = $art->add_file
	     (
	      $cfg,
	      filename => "t/t000load.t",
	      store => 0,
	     ) }, "displayName is required");
    like($@, qr/displayName must be non-blank/, "check message");
  }

  my $file = $art->add_file
    (
     $cfg,
     displayName => "test.txt",
     filename => "t/t000load.t",
     store => 0,
    );
  ok($file, "added a file");

  # check the content
  my $mine = read_file("t/t000load.t");
  my $stored = read_file($file->full_filename);
  is($stored, $mine, "check contents");

  # add some metadata
  my $name = "n" . time();
  my $meta = $file->add_meta
     (
      name => $name,
      value => "Test text",
     );
  ok($meta, "add meta data");
  is($meta->name, $name, "check name");
  is($meta->content_type, "text/plain", "check content type");
  ok($meta->is_text, "it qualifies as text");
  is($meta->value, "Test text", "check value");

  my @names = $file->metanames;
  ok(@names, "we got some meta names");
  my ($found) = grep $_ eq $name, @names;
  ok($found, "and found the meta name we added");

  my @meta = $file->metadata;
  ok(@meta, "we have some metadata");
  my ($found_meta) = grep $_->name eq $name, @meta;
  ok($found_meta, "and found the one we added");

  my @tmeta = $file->text_metadata;
  ok(@tmeta, "we have some text metadata");
  my ($found_tmeta) = grep $_->name eq $name, @tmeta;
  ok($found_tmeta, "and found the one we added");

  my $named = $file->meta_by_name($name);
  ok($named, "found added meta by name");

  my @info = $file->metainfo;
  ok(@info, "found metainfo");
  my ($info) = grep $_->{name} eq $name, @info;
  ok($info, "and found the info we added");

  my @files = $art->files;
  is (@files, 1, "should be one file");
  is($files[0]->id, $file->id, "should be what we added");

  my $file2 = $art->add_file
    (
     $cfg,
     displayName => "test2.txt",
     filename => "t/data/t101.jpg",
     store => 0,
     name => "test",
    );
  ok($file2, "add a second file (named)");
  $art->uncache_files;
  my $named_test = $art->file_by_name("test");
  ok($named_test, "got the named file");
  is($named_test->id, $file2->id, "and it's the file we added");
}

{
  {
    # fail adding an image
    my %errors;
    my $im = bse_add_image
      (
       $cfg, $art,
       file => "t/t000load.t",
       errors => \%errors,
      );
    ok(!$im, "image failed to add");
    ok($errors{image}, "failed on the image itself");
    is($errors{image}, "Unknown image file type", "check message");
  }
  {
    my %errors;
    my $im = bse_add_image
      (
       $cfg, $art,
       file => "t/data/govhouse.jpg",
       display_name => "test.php",
       errors => \%errors,
      );
    ok($im, "image failed to add");
    like($im->image, qr/\.jpeg$/, "check proper extension");
  }
}

{ # testing the indexing flags
  my $index = bse_make_article(cfg => $cfg,
			       title => "index test child",
			       parentid => $art->id);
  ok($index, "make article for should_index tests");
  ok($index->should_index, "default should be indexed");
  $index->set_listed(0);
  $index->uncache;
  ok(!$index->should_index, "not indexed if not listed");
  $index->set_flags("I");
  $index->uncache;
  ok($index->should_index, "indexed if I flag set");
  $index->set_listed(1);
  $index->set_flags("N");
  $index->uncache;
  ok(!$index->should_index, "not indexed if N flag set");
  $index->set_flags("C");
  $index->uncache;
  ok(!$index->should_index, "not indexed if C flag set");
  $index->set_flags("");
  $art->set_flags("C");
  $art->save;
  $index->uncache;
  ok(!$index->should_index, "not indexed if parent's C flag set");

  ok($index->remove($cfg), "remove index test");
  undef $index;

  END {
    $index->remove($cfg) if $index;
  }
}

ok($child->remove($cfg), "remove child");
undef $child;
ok($art->remove($cfg), "remove article");
undef $art;

{
  my $prefix = "g" . time;
  # deliberately out of order
  my $im1 = bse_add_global_image
    (
     $cfg,
     file => "t/data/govhouse.jpg",
     name => $prefix . "b"
    );
  ok($im1, "make a global image (b)");
  my $im2 = bse_add_global_image
    (
     $cfg,
     file => "t/data/govhouse.jpg",
     name => $prefix . "c"
    );
  ok($im2, "make a global image (c)");
  my $im3 = bse_add_global_image
    (
     $cfg,
     file => "t/data/govhouse.jpg",
     name => $prefix . "a"
    );
  ok($im3, "make a global image (a)");

  my $im4 = bse_add_global_image
    (
     $cfg,
     file => "t/data/govhouse.jpg",
    );
  ok($im4, "make a global image (no name)");

  my $site = bse_site();
  my @images = $site->images;
  cmp_ok(@images, '>=', 3, "we have some global images");

  my @mine = grep $_->name =~ /^\Q$prefix/, @images;

  # check sort order
  is($mine[0]->displayOrder, $im1->displayOrder, "first should be first");
  is($mine[1]->displayOrder, $im2->displayOrder, "middle should be middle");
  is($mine[2]->displayOrder, $im3->displayOrder, "last should be last");

  # fetch by name
  my $named = $site->image_by_name($prefix . "A");
  is($named->id, $im3->id, "check we got the right image by name");

  ok($im4->remove, "remove the global image (no name)");
  undef $im4;
  ok($im3->remove, "remove the global image");
  undef $im3;
  ok($im2->remove, "remove the global image");
  undef $im2;
  ok($im1->remove, "remove the global image");
  undef $im1;
  END {
    $im1->remove if $im1;
    $im2->remove if $im2;
    $im3->remove if $im3;
    $im4->remove if $im4;
  }
}

{ # test that access controls are removed on article removal
  # https://rt4.develop-help.com/Ticket/Display.html?id=1368
  my $art = bse_make_article(cfg => $cfg,
			     title => "010-api - access control");
  my $artid = $art->id; # save for later
  ok($art, "make an article");
  $art->add_group_id(-1);
  is_deeply([ $art->group_ids ], [ -1 ], "added group, check it stuck");

  # make an admin group
  require BSE::TB::AdminGroups;
  my $name = "010-api group " . time;
  my $group = BSE::TB::AdminGroups->make
    (
     name => $name,
    );
  ok($group, "make a group");

  require BSE::Permissions;
  my $perms = BSE::Permissions->new($cfg);
  $perms->set_article_perm($artid, $group, "");
  my $aperm = $perms->get_article_perm($artid, $group);
  ok($aperm, "added article perms for group");

  $art->remove($cfg);
  undef $art;
  # hack - taken from Article.pm
  my @now_ids =  map $_->{id}, BSE::DB->query(siteuserGroupsForArticle => $artid);
  is_deeply(\@now_ids, [], "should be no groups for that article id after article is removed");

  my $aperm2 = $perms->get_article_perm($artid, $group);
  ok(!$aperm2, "should no longer be admin permissions for that article/group");

  END {
    $art->remove($cfg) if $art;
    $group->remove if $group;
  }
}

END {
  $child->remove($cfg) if $child;
  $art->remove($cfg) if $art;
}
