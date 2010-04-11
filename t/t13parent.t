#!perl -w
use strict;
use BSE::Test qw(make_ua base_url);
use JSON;
use DevHelp::HTML;
use Test::More tests => 13;

my $ua = make_ua;
my $baseurl = base_url;

my $add_url = $baseurl . "/cgi-bin/admin/add.pl";

my @ajax_hdr = qw(X-Requested-With: XMLHttpRequest);

# make a parent
my $par = do_add($add_url, 
		 { 
		  parentid => -1,
		  title => "parent",
		 }, "make test parent");

# and a child
my $child = do_add($add_url, 
		 {
		  parentid => $par->{id},
		  title => "child",
		 }, "make test child");

{
  # attempt to reparent the parent under the child, should fail
  my $result = do_req($add_url, 
		      { 
		       save => 1, 
		       id=> $par->{id},
		       parentid => $child->{id},
		       lastModified => $par->{lastModified},
		      },
		      "reparent parent under child");
  ok(!$result->{success}, "should have failed")
    and print "# $result->{error_code}: $result->{message}\n";
}

do_req($add_url, { remove => 1, id => $child->{id} }, "remove child");
do_req($add_url, { remove => 1, id => $par->{id} }, "remove parent");

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
