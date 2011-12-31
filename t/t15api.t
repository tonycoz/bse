#!perl -w
use strict;
use BSE::Test qw(make_ua base_url);
use Test::More tests => 20;
use File::Spec;
use Carp qw(confess);

$SIG{__DIE__} = sub { confess @_ };

BEGIN {
  unshift @INC, File::Spec->catdir(BSE::Test::base_dir(), "cgi-bin", "modules");
}

BEGIN { use_ok("BSE::API", ":all") }

my $ua = make_ua();

my $base_cgi = File::Spec->catdir(BSE::Test::base_dir(), "cgi-bin");
ok(bse_init($base_cgi),   "initialize api")
  or print "# failed to bse_init in $base_cgi\n";
my $cfg = bse_cfg();
ok($cfg, "we have a cfg object");

my $art = bse_make_article(cfg => $cfg,
			   title => "API test");
ok($art, "make a basic article");

my $im1 = bse_add_image($cfg, $art, file => "t/data/t101.jpg");
ok($im1, "add an image, just a filename");

my $im2;
{
  open my $fh, "<", "t/data/t101.jpg"
    or die "Cannot open test image: $!\n";
  $im2 = bse_add_image($cfg, $art, fh => $fh, display_name => "t101.jpg");
  ok($im2, "add an image by fh");
}

# just set alt text
{
  my %errors;
  ok(bse_save_image($im1, alt => "Test", errors => \%errors),
     "update alt text");
  my $im = BSE::TB::Images->getByPkey($im1->id);
  ok($im, "found im1 independently");
  is($im->alt, "Test", "alt is set");
}

{ # change the image content (by name)
  my %errors;
  ok(bse_save_image($im1, file => "t/data/govhouse.jpg", errors => \%errors),
     "save new image content");
  is_deeply(\%errors, {}, "no errors");
  like($im1->src, qr(^/), "src should start with /, assuming no storage");
}

{ # change the image content (by fh)
  my %errors;
  open my $fh, "<", "t/data/govhouse.jpg"
    or die "Cannot open t/data/govhouse.jpg: $!";
  ok(bse_save_image($im2, fh => $fh, , display_name => "govhouse.jpg",
		    errors => \%errors),
     "save new image content (by fh)");
  is_deeply(\%errors, {}, "no errors");
  like($im2->src, qr(^/), "src should start with /, assuming no storage");
}

{
  # check we can retrieve the image
  my $src = base_url() . $im2->image_url;
  my $imres = $ua->get($src);
  open my $fh, "<", "t/data/govhouse.jpg"
    or die "Cannot open t/data/govhouse.jpg: $!";
  binmode $fh;
  my $orig = do { local $/; <$fh> };
  close $fh;
  ok($imres->is_success, "got some data");
  is($imres->decoded_content, $orig, "check it matches");
}

{
  # check thumbnailing
  my $thumb_url = base_url() . $im2->dynamic_thumb_url(geo => "editor");
  $thumb_url .= "&cache=0";
  print "# $thumb_url\n";
  my $thumb_res = $ua->get($thumb_url);
  ok($thumb_res->is_success, "successful fetch");
  like($thumb_res->content_type, qr(^image/[a-z]+$), "check content type");
  print "# ", $thumb_res->content_type, "\n";
}

ok($art->remove($cfg), "remove article");
