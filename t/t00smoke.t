#!perl -w
use strict;
use Test::More tests => 63;
use BSE::Test qw(make_ua fetch_ok base_url base_securl config);

++$|;
my $baseurl = base_url;
ok($baseurl =~ /^http:/, "basic check of base url");
my $securl = base_securl;
my $ua = make_ua;
fetch_ok($ua, "admin menu - check the site exists at all", "$baseurl/admin/", "Admin");
fetch_ok($ua, "generate all", "$baseurl/cgi-bin/admin/generate.pl",
	"html", "Title: BSE - Administration Centre");
fetch_ok($ua, "generate all verbose", 
	 "$baseurl/cgi-bin/admin/generate.pl?progress=1",
	 "Regenerating.*Return to admin menu");
fetch_ok($ua, "index", "$baseurl/", "Home");
fetch_ok($ua, "shop", "$baseurl/shop/", "The Shop");
fetch_ok($ua, "shop cart", "$baseurl/cgi-bin/shop.pl",
	 "Shopping Cart Items");
fetch_ok($ua, "shop cart checkout no items", "$baseurl/cgi-bin/shop.pl",
	 "Shopping Cart Items");
fetch_ok($ua, "build search index", "$baseurl/cgi-bin/admin/makeIndex.pl",
	 "html", "Title: BSE - Administration Centre");
fetch_ok($ua, "advanced search form", "$baseurl/cgi-bin/search.pl",
	 "All\\s+lower\\s+case");
fetch_ok($ua, "failed search", "$baseurl/cgi-bin/search.pl?q=blargle",
	 "No\\s+documents\\s+were\\s+found");
fetch_ok($ua, "good search", "$baseurl/cgi-bin/search.pl?q=shop",
	 qr!You\s+can\s+buy!s);
if (config->entry('site users', 'nopassword')) {
  fetch_ok($ua, "not user logon page", "$baseurl/cgi-bin/user.pl",
	   qr!Not\s+Authenticated!s);
}
else {
  fetch_ok($ua, "user logon page", "$baseurl/cgi-bin/user.pl",
	   qr!User\s+Logon!s);
}
fetch_ok($ua, "shop admin page", "$baseurl/cgi-bin/admin/shopadmin.pl",
	 qr!Shop\s+Administration!s);
fetch_ok($ua, "add article form", "$baseurl/cgi-bin/admin/add.pl",
	 qr!New\s+Page\sLev3!s);
fetch_ok($ua, "add catalog form", "$baseurl/cgi-bin/admin/add.pl?type=Catalog",
	 qr!Add\s+Catalog!s);
fetch_ok($ua, "add product form", "$baseurl/cgi-bin/admin/add.pl?type=Product",
	 qr!Add\s+product!s);
fetch_ok($ua, "edit article form", "$baseurl/cgi-bin/admin/add.pl?id=1",
	 qr!Edit\s+Page\s+Lev1!s);
fetch_ok($ua, "edit catalog form", "$baseurl/cgi-bin/admin/add.pl?id=4",
	 qr!Catalog\sDetails!s);
fetch_ok($ua, "user list", "$baseurl/cgi-bin/admin/adminusers.pl",
	 qr!Admin\sUsers!s);
fetch_ok($ua, "group list", "$baseurl/cgi-bin/admin/adminusers.pl?a_groups=1",
	 qr!Admin\sGroups!s);
fetch_ok($ua, "subscriptions", "$baseurl/cgi-bin/admin/subs.pl",
	 qr/Newsletter\s+List/);
fetch_ok($ua, "reports", "$baseurl/cgi-bin/admin/report.pl",
	 qr/Reports/);
# does a refresh unless the user is logged on
fetch_ok($ua, "changepw", "$baseurl/cgi-bin/admin/changepw.pl",
	 qr!Change Password|Security not enabled!i);
fetch_ok($ua, "printable", "$baseurl/cgi-bin/printable.pl?id=5",
	 qr!sidebar\s+subsection!i);
fetch_ok($ua, "printable error", "$baseurl/cgi-bin/printable.pl?id=5&template=foo",
	 qr!Invalid\s+template\s+name!i);
fetch_ok($ua, "siteusers", "$securl/cgi-bin/admin/siteusers.pl",
	 qr!Admin Site Members!i);

fetch_ok($ua, "reorder", "$securl/cgi-bin/admin/reorder.pl?parentid=-1",
	"html", "Title: BSE - Administration Centre");

fetch_ok($ua, 'fmail', "$baseurl/cgi-bin/fmail.pl",
	 qr!name="form"!);
fetch_ok($ua, 'page.pl?page=1', "$baseurl/cgi-bin/page.pl?page=1",
	 qr!welcome\s+to\s!i);
fetch_ok($ua, 'nadmin.pl/modules', "$baseurl/cgi-bin/admin/nadmin.pl/modules".
	qr/BSE\s+Modules/);
