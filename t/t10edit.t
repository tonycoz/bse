#!perl -w
use strict;
use BSE::Test qw(base_url make_ua fetch_ok skip check_form post_ok ok 
                 check_content);
#use WWW::Mechanize;
++$|;
print "1..24\n";
my $baseurl = base_url;
my $ua = make_ua;

ok($ua->get("$baseurl/cgi-bin/admin/add.pl?parentid=-1"), "edit page");
  check_content($ua->{content}, 'edit page',
  	      qr!No\s+parent\s+-\s+this\s+is\s+a\s+section
  	      .*
  	      common/default.tmpl
  	      .*
  	      Add\s+New\s+Section
	      !xs);
check_form($ua->{content},
	   "edit form",
	   parentid=>[ -1, 'select' ],
	   id => [ '', 'hidden' ],
	   titleImage => [ '', 'select' ],
	   template=> [ 'common/default.tmpl', 'select' ],
	   body => [ '<maximum of 64Kb>', 'textarea' ],
	   listed => [ 1, 'select' ],
	  );
$ua->field(title=>'Test Article');
$ua->field(body=>'This is a test body');
ok($ua->click('save'), 'submit modified edit form');
ok($ua->{res}->headers_as_string =~ /Refresh:\s+0\s*;\s+url=(\"?)([^\"\'\n\r;]+)(\1)/,
   "got refresh");
my $url = $2;
print "# $url\n";
ok($ua->get($url), "check admin mode url");
check_content($ua->{content}, "admin mode", 
  	   qr!
  	   <title>Test\ Server\ -\ Test\ Article</title>
  	   .*
  	   This\ is\ a\ test\ body
  	   !xsm);
