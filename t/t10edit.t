#!perl -w
use strict;
use BSE::Test qw(base_url make_ua fetch_ok skip check_form post_ok ok);

++$|;
print "1..25\n";
my $baseurl = base_url;
my $ua = make_ua;
my $headers;
my $content = 
  fetch_ok($ua, "edit page", 
	   "$baseurl/cgi-bin/admin/add.pl?level=1&parentid=-1",
	   qr!No\s+parent\s+-\s+this\s+is\s+a\s+section
	   .*
	   common/default.tmpl
	   .*
	   Add\s+New\s+Section
	   !xs);
if ($content) {
  check_form($content,
	     "edit form",
	     parentid=>[ -1, 'select' ],
	     id => [ '', 'hidden' ],
	     titleImage => [ '', 'select' ],
	     template=> [ 'common/default.tmpl', 'select' ],
	     body => [ '<maximum of 64Kb>', 'textarea' ],
	     listed => [ 1, 'select' ],
	     );
}
else {
  skip("no content to check", 18);
}

my ($code, $good);
($content, $code, $good, $headers) = 
  post_ok($ua, "adding article", "$baseurl/cgi-bin/admin/add.pl",
	  [
	   parentid=>-1,
	   level => 1,
	   title=>"Test Article",
	   titleImage=>'',
	   template=>'common/default.tmpl',
	   body=>'This is a test body',
	   release=>'',
	   expire=>'',
	   summaryLength => '',
	   displayThreshold=>'',
	   keywords=>'',
	   listed=>1,
	   save=>1,
	  ], undef, qr!Refresh:\s+0!);
if ($good) {
  $headers =~ /Refresh:\s+\d+\s*;\s+url=(\"?)([^\"\'\n\r;]+)(\1)/
    or die "Someone lied";
  my $url = $2;
  print "# $url\n";
  ok($url =~ m!/cgi-bin/admin/admin\.pl\?!, "check admin mode url");
  fetch_ok($ua, "admin mode", $url,
	   qr!
	   <title>Test\ Server\ -\ Test\ Article</title>
	   .*
	   This\ is\ a\ test\ body
	   !xsm);
}
else {
  skip(3);
}
