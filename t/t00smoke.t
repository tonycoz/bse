#!perl -w
use strict;
use BSE::Test;

++$|;
print "1..27\n";
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
fetch_ok($ua, "good search", "$baseurl/cgi-bin/search.pl?q=title",
	 qr!My\s+site(?:'|&\#39;)s\s+title.*\[formatting\s+guide!s);
fetch_ok($ua, "user logon page", "$baseurl/cgi-bin/user.pl",
	 qr!User\s+Logon!s);

