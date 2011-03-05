#!perl -w
use strict;
use BSE::Test qw(base_url make_ua fetch_ok skip check_form post_ok ok 
                 check_content);
#use WWW::Mechanize;
++$|;
print "1..19\n";
my $baseurl = base_url;
my $ua = make_ua;

ok($ua->get("$baseurl/cgi-bin/admin/add.pl?parentid=-1"), "edit page");
  check_content($ua->{content}, 'edit page',
  	      qr!No\s+parent\s+-\s+this\s+is\s+a\s+section
  	      .*
  	      common/default.tmpl
  	      .*
  	      Add\s+New\s+Page\s+Lev1
	      !xs);
check_form($ua->{content},
	   "edit form",
	   parentid=>[ -1, 'select' ],
	   id => [ '', 'hidden' ],
	   template=> [ 'common/default.tmpl', 'select' ],
	   body => [ '', 'textarea' ],
	   listed => [ 1, 'select' ],
	  );
$ua->field(title=>'Test Article');
$ua->field(body=>'This is a test body');
ok($ua->click('save'), 'submit modified edit form');
# should redirect to admin mode page
check_content($ua->{content}, "admin mode", 
  	   qr!
  	   <title>.*Test\ Article.*</title>
  	   .*
  	   This\ is\ a\ test\ body
  	   !xsm);
