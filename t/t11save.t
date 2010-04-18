#!perl -w
use strict;
use BSE::Test qw(make_ua base_url);
use JSON;
use DevHelp::HTML;
use Test::More tests => 193;

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

sub do_req {
  my ($url, $req_data, $comment) = @_;

  my $content = join "&", map "$_=" . escape_uri($req_data->{$_}), keys %$req_data;
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
