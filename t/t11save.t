#!perl -w
use strict;
use BSE::Test qw(make_ua base_url);
use JSON;
use DevHelp::HTML;
use Test::More;
use Article;

my @cols = Article->columns;

my $base = 113;

my $count = $base + (@cols - 13) * 4;

plan tests => $count;

$| = 1;

my $ua = make_ua;
my $baseurl = base_url;

my $add_url = $baseurl . "/cgi-bin/admin/add.pl";

my @ajax_hdr = qw(X-Requested-With: XMLHttpRequest);

my %add_req =
  (
   save => 1,
   title => "test",
   parentid => -1,
   _context => "test context",
  );
my $art_data = do_req($add_url, \%add_req, "add article");

SKIP:
{
  $art_data or skip("no response to add", 20);
  ok($art_data->{success}, "successful json response");

  is($art_data->{context}, "test context", "check context returned");

  my $art = $art_data->{article};
  my $orig_lastmod = $art->{lastModified};

  # try to fetch by id
 SKIP:
  {
    my %fetch_req =
      (
       a_article => 1,
       id => $art->{id},
      );
    my $data = do_req($add_url, \%fetch_req, "fetch just saved")
      or skip("no json", 2);
    ok($data->{success}, "successful");
    ok($data->{article}, "has an article");
    my %temp = %$art;
    for my $field (qw/release expire/) {
      delete $temp{$field};
      delete $data->{article}{$field};
    }
    is_deeply($data->{article}, \%temp, "check it matches what we saved");
    ok($data->{article}{tags}, "has a tags member");
    is_deeply($data->{article}{tags}, [], "which is an empty array ref");
  }

  my @fields = grep 
    {
      defined $art->{$_}
	&& !/^(id|created|link|admin|files|images|cached_dynamic|createdBy|generator|level|lastModified(By)?|displayOrder)$/
	  && !/^thumb/
	} keys %$art;

  for my $field (@fields) {
    print "# save test $field\n";
    my %reqdata =
      (
       save => 1,
       id => $art->{id},
       $field => $art->{$field},
       lastModified => $art->{lastModified},
      );
    my $data = do_req($add_url, \%reqdata, "set $field");
  SKIP:
    {
      $data or skip("Not json from setting $field", 2);
      ok($data->{success}, "success flag is set");
      ok($data->{article}, "has an article object");
      $art = $data->{article};
    }
  }

  my $tag_name1 = "YHUIOP";
  my $tag_name2 = "zyx: alpha";
  { # save tags
    my %reqdata =
      (
       save => 1,
       id => $art->{id},
       _save_tags => 1,
       tags => [ $tag_name2, " $tag_name1 " ],
       lastModified => $art->{lastModified},
      );
    my $data = do_req($add_url, \%reqdata, "set tags");
  SKIP:
    {
      $data or skip("Not json from setting tags", 2);
      ok($data->{success}, "success flag set");
      is_deeply($data->{article}{tags}, [ $tag_name1, $tag_name2 ],
		"check tags saved");
      $art = $data->{article};
    }
  }

  { # grab the tree
    my %tree_req =
      (
       a_tree => 1,
       id => -1,
      );
    my $data = do_req($add_url, \%tree_req, "fetch tree");
    $data or skip("not a json response", 6);
    ok($data->{success}, "was successful");
    ok($data->{articles}, "has articles");
    my $art = $data->{articles}[0];
    ok(defined $art->{level}, "entries have level");
    ok($art->{title}, "entries have a title");
    ok(defined $art->{listed}, "entries have a listed");
    ok($art->{lastModified}, "entries have a lastModified");
  }

  { # grab the tags
    my %tag_req =
      (
       a_tags => 1,
       id => -1,
      );
    my $data = do_req($add_url, \%tag_req, "fetch tags");
  SKIP:
    {
      $data or skip("not a json response", 4);
      ok($data->{tags}, "it has tags");
      my ($xyz_tag) = grep $_->{name} eq $tag_name2, @{$data->{tags}};
      ok($xyz_tag, "check we found the tag we set");
      is($xyz_tag->{cat}, "zyx", "check cat");
      is($xyz_tag->{val}, "alpha", "check val");
    }
  }

  my $tag1;
  my $tag2;
  { # grab them with article ids
    my %tag_req =
      (
       a_tags => 1,
       id => -1,
       showarts => 1,
      );
    my $data = do_req($add_url, \%tag_req, "fetch tags");
  SKIP:
    {
      $data or skip("not a json response", 6);
      ok($data->{tags}, "it has tags");
      ($tag1) = grep $_->{name} eq $tag_name1, @{$data->{tags}};
      ($tag2) = grep $_->{name} eq $tag_name2, @{$data->{tags}};
      ok($tag2, "check we found the tag we set");
      is($tag2->{cat}, "zyx", "check cat");
      is($tag2->{val}, "alpha", "check val");
      ok($tag2->{articles}, "has articles");
      ok(grep($_ == $art->{id}, @{$tag2->{articles}}),
	      "has our article id in it");
    }
  }

 SKIP:
  { # delete a tag globally
    $tag2
      or skip("didn't find the tag we want to remove", 6);
    my %del_req =
      (
       a_tagdelete => 1,
       id => -1,
       tag_id => $tag2->{id},
      );
    my $data = do_req($add_url, \%del_req, "delete tag");
  SKIP:
    {
      $data or skip("not a json response", 7);
      ok($data->{success}, "successful");

      # refetch tag list and make sure it's gone
      my %get_req =
	(
	 a_tags => 1,
	 id => -1,
	);
      my $tags_data = do_req($add_url, \%get_req, "refetch tags");
      my ($tag) = grep $_->{name} eq $tag_name2, @{$data->{tags}};
      ok(!$tag, "should be gone");

      # try to delete it again
      my $redel_data = do_req($add_url, \%del_req, "delete should fail");
      $redel_data
	or skip("not a json response", 3);
      ok(!$redel_data->{success}, "should fail");
      is($redel_data->{error_code}, "FIELD", "check error code");
      ok($redel_data->{errors}{tag_id}, "and error message on field");
    }
  }

  { # rename a tag
    my %ren_req =
      (
       a_tagrename => 1,
       id => -1,
       tag_id => $tag1->{id},
       name => $tag_name2, # rename over just removed tag
      );

    my $data = do_req($add_url, \%ren_req, "rename tag");
  SKIP:
    {
      $data
	or skip("not a json response", 4);
      ok($data->{success}, "successful");
      ok($data->{tag}, "returned updated tag");
      is($data->{tag}{name}, $tag_name2, "check name saved");
    }
  }

  { # refetch the article to check the tags
    my %fetch_req =
      (
       a_article => 1,
       id => $art->{id},
      );
    my $data = do_req($add_url, \%fetch_req, "fetch just saved")
      or skip("no json", 2);
    ok($data->{success}, "check success");
    is_deeply($data->{article}{tags}, [ $tag_name2 ],
	      "check the tags");
  }

  # error handling on save
 SKIP:
  { # bad title
    my %bad_title =
      (
       save => 1,
       id => $art->{id},
       title => "",
       lastModified => $art->{lastModified},
      );
    my $data = do_req($add_url, \%bad_title, "save bad title");
    $data or skip("not a json response", 2);
    ok(!$data->{success}, "should be failure");
    is($data->{error_code}, "FIELD", "should be a field error");
    ok($data->{errors}{title}, "should be a message for the title");
  }
 SKIP:
  { # bad template
    my %bad_template =
      (
       save => 1,
       id => $art->{id},
       template => "../../etc/passwd",
       lastModified => $art->{lastModified},
      );
    my $data = do_req($add_url, \%bad_template, "save bad template");
    $data or skip("not a json response", 2);
    ok(!$data->{success}, "should be failure");
    is($data->{error_code}, "FIELD", "should be a field error");
    ok($data->{errors}{template}, "should be a message for the template");
  }
 SKIP:
  { # bad last modified
    my %bad_lastmod =
      (
       save => 1,
       id => $art->{id},
       title => "test",
       lastModified => $orig_lastmod,
      );
    my $data = do_req($add_url, \%bad_lastmod, "save bad lastmod");
    $data or skip("not a json response", 2);
    ok(!$data->{success}, "should be failure");
    is($data->{error_code}, "LASTMOD", "should be a last mod error");
  }
 SKIP:
  { # bad parent
    my %bad_parent =
      (
       save => 1,
       id => $art->{id},
       parentid => $art->{id},
       lastModified => $art->{lastModified},
      );
    my $data = do_req($add_url, \%bad_parent, "save bad parent");
    $data or skip("not a json response", 2);
    ok(!$data->{success}, "should be failure");
    is($data->{error_code}, "PARENT", "should be a parent error");
  }

  # grab config data for the article
 SKIP:
  {
    my %conf_req =
      (
       a_config => 1,
       id => $art->{id},
      );
    my $data = do_req($add_url, \%conf_req, "config data");
    $data or skip("no json to check", 7);
    ok($data->{success}, "check for success");
    ok($data->{templates}, "has templates");
    ok($data->{thumb_geometries}, "has geometries");
    ok($data->{defaults}, "has defaults");
    ok($data->{child_types}, "has child types");
    is($data->{child_types}[0], "Article", "check child type value");
    ok($data->{flags}, "has flags");
  }

 SKIP:
  { # config article for children of the article
    my %conf_req =
      (
       a_config => 1,
       parentid => $art->{id},
      );
    my $data = do_req($add_url, \%conf_req, "config data");
    $data or skip("no json to check", 3);
    ok($data->{success}, "check for success");
    ok($data->{templates}, "has templates");
    ok($data->{thumb_geometries}, "has geometries");
    ok($data->{defaults}, "has defaults");
  }

 SKIP:
  { # section config
    my %conf_req =
      (
       a_config => 1,
       parentid => -1,
      );
    my $data = do_req($add_url, \%conf_req, "section config data");
    $data or skip("no json to check", 3);
    ok($data->{success}, "check for success");
    ok($data->{templates}, "has templates");
    ok($data->{thumb_geometries}, "has geometries");
    ok($data->{defaults}, "has defaults");
    use Data::Dumper;
    note(Dumper($data));
  }

 SKIP:
  {
    my $parent = do_add($add_url, { parentid => -1, title => "parent" }, "add parent");
    my $kid1 = do_add($add_url, { parentid => $parent->{id}, title => "kid1" }, "add first kid");
    sleep 2;
    my $kid2 = do_add($add_url,
		      {
		       parentid => $parent->{id},
		       title => "kid2",
		       _after => $kid1->{id},
		      }, "add second child");
    my @expected_order = ( $kid1->{id}, $kid2->{id} );
    my %tree_req =
      (
       a_tree => 1,
       id => $parent->{id},
      );
    my $data = do_req($add_url, \%tree_req, "get newly ordered tree");
    ok($data->{success}, "got the tree");
    my @saved_order = map $_->{id}, @{$data->{articles}};
    is_deeply(\@saved_order, \@expected_order, "check saved order");

    {
      {
	# stepkids
	my %add_step =
	  (
	   add_stepkid => 1,
	   id => $parent->{id},
	   stepkid => $art->{id},
	   _after => $kid1->{id},
	  );
	sleep(2);
	my $result = do_req($add_url, \%add_step, "add stepkid in order");
	ok($result->{success}, "Successfully");
	my $rel = $result->{relationship};
	ok($rel, "has a relationship");
	is($rel->{childId}, $art->{id}, "check the rel child id");
	is($rel->{parentId}, $parent->{id}, "check the rel parent id");
      }

      {
	# refetch the tree
	my $data = do_req($add_url, \%tree_req, "get tree with stepkid");
	my @expected_order = ( $kid1->{id}, $art->{id}, $kid2->{id} );
	my @found_order = map $_->{id}, @{$data->{allkids}};
	is_deeply(\@found_order, \@expected_order, "check new order");
      }

      {
	# remove the stepkid
	my %del_step =
	  (
	   del_stepkid => 1,
	   id => $parent->{id},
	   stepkid => $art->{id},
	   _after => $kid1->{id},
	  );
	my $result = do_req($add_url, \%del_step, "delete stepkid");
	ok($result->{success}, "check success");

	$result = do_req($add_url, \%del_step, "delete stepkid again (should failed)");
	ok(!$result->{success}, "it failed");

	my $data = do_req($add_url, \%tree_req, "get tree with stepkid removed");
	my @expected_order = ( $kid1->{id}, $kid2->{id} );
	my @found_order = map $_->{id}, @{$data->{allkids}};
	is_deeply(\@found_order, \@expected_order, "check new order with stepkid removed");
      }
    }

    do_req($add_url, { remove => 1, id => $kid1->{id} }, "remove kid1");
    do_req($add_url, { remove => 1, id => $kid2->{id} }, "remove kid2");
    do_req($add_url, { remove => 1, id => $parent->{id} }, "remove parent");
  }

  # delete it
 SKIP:
  {
    my %del_req =
      (
       remove => 1,
       id => $art->{id},
       _context => $art->{id},
      );
    my $data = do_req($add_url, \%del_req, "remove test article");
    $data or skip("no json from req", 3);
    ok($data->{success}, "successfully deleted");
    is($data->{article_id}, $art->{id}, "check id returned");
    is($data->{context}, $art->{id}, "check context returned");
  }

  # shouldn't be fetchable anymore
 SKIP:
  {
    my %fetch_req =
      (
       a_article => 1,
       id => $art->{id},
      );
    my $data = do_req($add_url, \%fetch_req, "fetch just deleted")
      or skip("no json", 2);
    ok(!$data->{success}, "failed as expected");
  }
}

SKIP:
{ # tag cleanup
  my %clean_req =
    (
     a_tagcleanup => 1,
     id => -1,
    );
  my $data = do_req($add_url, \%clean_req, "tag cleanup");
  $data
    or skip("no json response", 2);
  ok($data->{success}, "successful");
  ok($data->{count}, "should have cleaned up something");
}

sub do_req {
  my ($url, $req_data, $comment) = @_;

  my @entries;
  for my $key (keys %$req_data) {
    my $value = $req_data->{$key};
    if (ref $value) {
      for my $val (@$value) {
	push @entries, "$key=" . escape_uri($val);
      }
    }
    else {
      push @entries, "$key=" . escape_uri($value);
    }
  }
  my $content = join("&", @entries);

  print <<EOS;
# Request:
# URL: $add_url
# Content: $content
EOS

  my $req = HTTP::Request->new(POST => $add_url, \@ajax_hdr);

  $req->content($content);

  my $resp = $ua->request($req);
  ok($resp->is_success, "$comment successful at http level");
  my $data = eval { from_json($resp->decoded_content) };
  ok($data, "$comment response decoded as json")
    or print "# $@\n";

  return $data;
}

sub do_add {
  my ($url, $req, $comment) = @_;

  $req->{save} = 1;

  my $result = do_req($url, $req, $comment);
  my $article;
 SKIP:
  {
    $result or skip("No JSON result", 1);
    if (ok($result->{success} && $result->{article}, "check success and article")) {
      return $result->{article};
    }
  };

  return;
}
