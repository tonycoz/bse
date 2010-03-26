#!perl -w
use strict;
use BSE::Test qw(make_ua base_url ok);
use JSON;
use DevHelp::HTML;

print "1..95\n";
my $ua = make_ua;
my $baseurl = base_url;

my $add_url = $baseurl . "/cgi-bin/admin/add.pl";

my @ajax_hdr = qw(X-Requested-With: XMLHttpRequest);

my $req = HTTP::Request->new(POST => $add_url, \@ajax_hdr);

$req->content("save=1&title=test&parentid=-1");

my $resp = $ua->request($req);
ok($resp->is_success, "successfully added");
my $art_data = eval { from_json($resp->decoded_content) };
ok($art_data, "parsed response as json")
  or diag $@;
ok($art_data->{success}, "successful json response");

my $art = $art_data->{article};
my @fields = grep 
  {
    defined $art->{$_}
      && !/^(id|created|link|admin|files|images|cached_dynamic|createdBy|generator|level|lastModified(By)?|displayOrder)$/
	&& !/^thumb/
  } keys %$art;

for my $field (@fields) {
  print "# save test $field\n";
  my $content = "save=1&id=$art->{id}&$field=" . escape_uri($art->{$field});
  my $req = HTTP::Request->new(POST => $add_url, \@ajax_hdr);

  $req->content($content);

  my $resp = $ua->request($req);
  ok($resp->is_success, "save $field successful at http level");
  my $data = eval { from_json($resp->decoded_content) };
  ok($data, "decoded as json");
  ok($data->{success}, "success flag is set");
  ok($data->{article}, "has an article object");
}
