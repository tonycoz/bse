#!perl -w
use strict;
use BSE::Test;

++$|;
print "1..45\n";
my $baseurl = base_url;
ok($baseurl =~ /^http:/, "basic check of base url");
my $ua = make_ua;
fetch_ok($ua, "admin menu - check the site exists at all", "$baseurl/admin/", "Admin");
fetch_ok($ua, "generate all", "$baseurl/cgi-bin/admin/generate.pl",
	"html", "Refresh: 0; .*/admin/");
fetch_ok($ua, "generate all verbose", 
	 "$baseurl/cgi-bin/admin/generate.pl?progress=1",
	 "Regenerating your site.*Return to admin menu");
fetch_ok($ua, "index", "$baseurl/", "Home");
fetch_ok($ua, "shop", "$baseurl/shop/", "The Shop - Catalogue Items");
fetch_ok($ua, "shop cart", "$baseurl/cgi-bin/shop.pl",
	 "Shopping Cart Items");
fetch_ok($ua, "shop cart checkout no items", "$baseurl/cgi-bin/shop.pl",
	 "Shopping Cart Items");
fetch_ok($ua, "build search index", "$baseurl/cgi-bin/admin/makeIndex.pl",
	 "html", "Refresh: 0; .*/admin/");
fetch_ok($ua, "advanced search form", "$baseurl/cgi-bin/search.pl",
	 "All\\s+lower\\s+case");
fetch_ok($ua, "failed search", "$baseurl/cgi-bin/search.pl?q=blargle",
	 "No\\s+documents\\s+were\\s+found");
fetch_ok($ua, "good search", "$baseurl/cgi-bin/search.pl?q=shop",
	 qr!You\s+can\s+buy!s);
fetch_ok($ua, "user logon page", "$baseurl/cgi-bin/user.pl",
	 qr!User\s+Logon!s);
fetch_ok($ua, "shop admin page", "$baseurl/cgi-bin/admin/shopadmin.pl",
	 qr!Shop\s+administration!s);
fetch_ok($ua, "add article form", "$baseurl/cgi-bin/admin/add.pl",
	 qr!New\s+Page\sLev3!s);
fetch_ok($ua, "add catalog form", "$baseurl/cgi-bin/admin/add.pl?type=Catalog",
	 qr!New\s+Catalog!s);
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
	 qr/Subscriptions\s+List/);
