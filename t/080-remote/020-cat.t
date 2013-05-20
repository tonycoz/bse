#!perl -w
use strict;
use BSE::Test qw(make_ua base_url);
use JSON;
use DevHelp::HTML;
use Test::More tests => 34;
use Data::Dumper;

my $ua = make_ua;
my $baseurl = base_url;

my $add_url = $baseurl . "/cgi-bin/admin/add.pl";

my @ajax_hdr = qw(X-Requested-With XMLHttpRequest);

# make a catalog
my $cat = do_add($add_url, 
		 { 
		  parentid => 3,
		  title => "Test Catalog",
		  type => "Catalog",
		 }, "make test catalog");

is($cat->{generator}, "Generate::Catalog", "make sure it's a catalog");

# and an article
my $art = do_add($add_url, 
		 {
		  parentid => -1,
		  title => "Test article",
		 }, "make test article");

is($art->{generator}, "Generate::Article", "make sure it's an article");

my $prod;
{
  # make a product
  my $result = do_add
    ($add_url,
     {
      type => "Product",
      parentid => $cat->{id},
      title => "Some Product",
     }, "make test product");
  is($result->{generator}, "Generate::Product",
     "check generator");
  $prod = $result;
}

{
  # fail to make a product (empty title)
  my $result = do_req
    ($add_url,
     {
      type => "Product",
      parentid => $cat->{id},
      title => "",
      save => 1,
     }, "fail to make a product");
  ok(!$result->{success}, "yep, it failed");
  is($result->{error_code}, "FIELD", "and correct error code");
  ok($result->{errors}{title}, "has a title error");
}

{ # fail to set empty title for a product
  my $result = do_req
    ($add_url,
     {
      id => $prod->{id},
      title => "",
      lastModified => $prod->{lastModified},
      save => 1,
     }, "fail to set title to empty");
  ok(!$result->{success}, "yep, it failed");
  is($result->{error_code}, "FIELD", "and correct error code");
  ok($result->{errors}{title}, "has a title error");
}

{
  # attempt to reparent the article under the catalog, should fail
  my $result = do_req($add_url, 
		      { 
		       save => 1, 
		       id=> $art->{id},
		       parentid => $cat->{id},
		       lastModified => $art->{lastModified},
		      },
		      "reparent article under catalog");
  ok(!$result->{success}, "should have failed")
    and print "# $result->{error_code}: $result->{message}\n";
}
{
  # and the other way around
  my $result = do_req($add_url, 
		      { 
		       save => 1, 
		       id=> $cat->{id},
		       parentid => $art->{id},
		       lastModified => $cat->{lastModified},
		      },
		      "reparent catalog under article");
  ok(!$result->{success}, "should have failed")
    and print "# $result->{error_code}: $result->{message}\n";
}

do_req($add_url, { remove => 1, id => $prod->{id} }, "remove product");
do_req($add_url, { remove => 1, id => $art->{id} }, "remove article");
do_req($add_url, { remove => 1, id => $cat->{id} }, "remove catalog");

sub do_req {
  my ($url, $req_data, $comment) = @_;

  my $content = join "&", map "$_=" . escape_uri($req_data->{$_}), keys %$req_data;
  my $req = HTTP::Request->new(POST => $add_url, \@ajax_hdr);

  $req->content($content);
  
  my $resp = $ua->request($req);
  ok($resp->is_success, "$comment successful at http level");
  my $data = eval { from_json($resp->decoded_content) };
  ok($data, "$comment response decoded as json")
    or print "# $@: ", $resp->decoded_content, "\n";

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

    print STDERR Dumper($result);
  };

  return;
}
