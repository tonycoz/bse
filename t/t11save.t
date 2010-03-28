#!perl -w
use strict;
use BSE::Test qw(make_ua base_url);
use JSON;
use DevHelp::HTML;
use Test::More tests => 124;

my $ua = make_ua;
my $baseurl = base_url;

my $add_url = $baseurl . "/cgi-bin/admin/add.pl";

my @ajax_hdr = qw(X-Requested-With: XMLHttpRequest);

my %add_req =
  (
   save => 1,
   title => "test",
   parentid => -1,
  );
my $art_data = do_req($add_url, \%add_req, "add article");

SKIP:
{
  $art_data or skip("no response to add", 20);
  ok($art_data->{success}, "successful json response");

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

  # delete it
 SKIP:
  {
    my %del_req =
      (
       remove => 1,
       id => $art->{id},
      );
    my $data = do_req($add_url, \%del_req, "remove test article");
    $data or skip("no json from req");
    ok($data->{success}, "successfully deleted");
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
