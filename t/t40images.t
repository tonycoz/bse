#!perl -w
use strict;
use BSE::Test qw(make_ua base_url fetch_ok follow_ok click_ok follow_refresh_ok);
use Test::More tests => 122;

my $base_url = base_url;
my $ua = make_ua;

# make a new section to put the images into
fetch_ok($ua, "menu", "$base_url/cgi-bin/admin/menu.pl", qr/Administration Centre/);

follow_ok($ua, "add section link", "Add a new section", qr/New Page Lev1/);

ok($ua->form("edit"), "select edit form");

$ua->field(title => "Images test article");
$ua->field(body => "ONE((image[test]))\n\nTWO\{\{image[2]\}\}");

click_ok($ua, "add the article", "save", undef, qr/Refresh/);

follow_refresh_ok($ua, "refresh to article display");

ok($ua->form("edit"), "select edit form");

click_ok($ua, "back to editor", undef, qr/Edit Page Lev1/);

follow_ok($ua, "to images", "Manage Images", qr/Page Lev1 Image Wizard/);

ok($ua->form("add"), "select add form");

my @image_content = ( image1(), image2() );

my $form = $ua->current_form;
ok(my $file = $form->find_input("image"), "get file field");
$file->filename("t105pal.gif");
$file->content($image_content[0]);

$ua->field(name => 'test');
$ua->field(altIn => 'one');

click_ok($ua, "add an image", 'addimg', undef, qr/Refresh/);

follow_refresh_ok($ua, "refresh back to image wizard", "Page Lev1 Image Wizard");

ok($ua->form('add'), "add form again");

$form = $ua->current_form;
ok($file = $form->find_input("image"), "get file field");
$file->filename("t101.jpg");
$file->content($image_content[1]);
$ua->field(altIn => 'two');

click_ok($ua, "add second image", "addimg", undef, qr/Refresh/);

follow_refresh_ok($ua, "refresh back to image wizard", 
		  "Page Lev1 Image Wizard");

follow_ok($ua, "back to editor", "Edit article", "Edit Page Lev1");

# remember where we are
my $edit_url = $ua->uri;

# this page should include the two images we added
my @images = get_images($ua->content);

ok(@images == 2, "two images");
is($images[0]{height}, 16, "image 1 height");
is($images[0]{width}, 16, "image 1 width");
like($images[0]{src}, qr/t105pal\.gif$/, "image 1 name");
is($images[0]{alt}, "one", "image 1 alt");
is($images[1]{height}, 150, "image 2 height");
is($images[1]{width}, 150, "image 2 width");
like($images[1]{src}, qr/t101\.jpg$/, "image 2 name");
is($images[1]{alt}, "two", "image 2 alt");

# look at the article
follow_ok($ua, "admin view of article", "See article", "Images test article");

# extract the images here too, but simpler due to the layout of the body
my @im_html;
($im_html[0]) = $ua->content =~ /ONE\(\((.*?)\)\)/;
($im_html[1]) = $ua->content =~ /TWO\{\{(.*?)\}\}/;
for my $im_index (0..1) {
  my %im;

  my $im_html = $im_html[$im_index];

  ok($im_html, "image $im_index sequence found in body");
  while ($im_html =~ /(\w+)=\"([^\"]+)\"/g) {
    $im{$1} = $2;
  }

  # match the fields
  for my $field (qw(image alt width height)) {
    is($im{$field}, $images[$im_index]{$field}, "image $im_index field $field match");
  }
  
  # make sure we can fetch the images
  # workaround: get() doesn't push the page stack
  $ua->_push_page_stack();
  my $image_abs = URI->new_abs($im{src}, $ua->uri);
  fetch_ok($ua, "image $im_index", $image_abs);

  # make sure it matches
  is($ua->content(), $image_content[$im_index],
     "image content stored correctly");
  
  # go back to the containing page
  $ua->back();
}

ok($ua->form("edit"), "select edit form");

click_ok($ua, "back to editor", undef, qr/Edit Page Lev1/);

follow_ok($ua, "admin menu", "Admin menu", qr/Administration Centre/);

follow_ok($ua, "sections", "Administer sections", qr/Manage Sections/);

follow_ok($ua, "global images", "Global Images", qr/Global Image Wizard/);

# fail to add a global image
ok($ua->form('add'), "add form");
$form = $ua->current_form;
ok($file = $form->find_input("image"), "get file field");
$file->filename("t105_trans.gif");
$file->content(imageg());
$ua->field(altIn => 'three');

# this should fail, since we didn't set a name
click_ok($ua, "fail to add a global image", "addimg", 
	 qr/Name must be supplied for global images/);

# try again, and supply a name
my $global_name = "test".time;
ok($ua->form('add'), "add form");
$form = $ua->current_form;
ok($file = $form->find_input("image"), "get file field");
$file->filename("t105_trans.gif");
$file->content(imageg());
$ua->field(altIn => 'three');
$ua->field(name => $global_name);

click_ok($ua, "add a global image", 'addimg', undef, qr/Refresh/);

follow_refresh_ok($ua, "refresh back to image wizard", "Global Image Wizard");

# back to the article
print "# edit url $edit_url\n";
fetch_ok($ua, "back to edit", $edit_url, qr/Edit Page Lev1/);

# update the body to reference the global image
ok($ua->form("edit"), "select edit form");
$ua->field(body =>"ONE((image[test]))\n\nTWO\{\{image[2]\}\}\n\nTHREE<<gimage[$global_name]>>");

click_ok($ua, "save the new body", "save", undef, qr/Refresh/);
follow_refresh_ok($ua, "refresh back to edit");
follow_ok($ua, "to display", "See article", qr/Images test article/);
print "# on page ",$ua->uri,"\n";
my ($g_html) = $ua->content =~ /THREE&lt;&lt;(.*?)&gt;&gt;/;
ok($g_html, "global image in page");
print "# g_html $g_html\n";
my %gim;
while ($g_html =~ /(\w+)=\"([^\"]+)\"/g) {
  $gim{$1} = $2;
}

is($gim{width}, 20, "gimage width");
is($gim{height}, 20, "gimage height");
is($gim{alt}, "three", "gimage alt");

# check that the image matches
$ua->_push_page_stack();
my $gimage_abs = URI->new_abs($gim{src}, $ua->uri);
fetch_ok($ua, "gimage content", $gimage_abs);

is($ua->content, imageg(), "gimage content");
$ua->back;

# back to the editor
ok($ua->form("edit"), "select edit form");
click_ok($ua, "edit page", undef, qr/Edit Page Lev1/);

follow_ok($ua, "image manager", "Manage Images", qr/Page Lev1 Image Wizard/);

for my $im_index (0 .. 1) {
  follow_ok($ua, "delete image $im_index", "Delete", undef, qr/Refresh/);
  follow_refresh_ok($ua, "back to display");

  # make sure the file was deleted
  $ua->_push_page_stack();
  my $img_url = URI->new_abs($images[$im_index]{src}, $ua->uri);
  ok(!$ua->get($img_url)->is_success, 
     "checking image file for $im_index was deleted");
  $ua->back;
}

follow_ok($ua, "admin menu", "Admin menu", qr/Administration Centre/);
follow_ok($ua, "sections", "Administer sections", qr/Manage Sections/);
follow_ok($ua, "global images", "Global Images", qr/Global Image Wizard/);

# since there may have been other global images, we need to be a bit 
# more careful here
my $links = $ua->extract_links;
my @links = grep $_->[1] eq 'Delete', @$links;
print "# link #", scalar(@links), "\n";
follow_ok($ua, "delete global image", 
	  { n=>scalar(@links), text=>"Delete" }, 
	  undef, qr/Refresh/);
follow_refresh_ok($ua, "back to display");

# make sure the file was deleted
$ua->_push_page_stack();
my $img_url = URI->new_abs($gim{src}, $ua->uri);
ok(!$ua->get($img_url)->is_success, 
   "checking image file for global image was deleted");
$ua->back;

sub image1 {
  # based on testout/t105pal.gif from Imager
  my $hex = <<HEX;
47 49 46 38 37 61 10 00 10 00 A2 00 00 FF FF 00 
FF 00 00 00 FF 00 00 00 FF 00 00 00 FF FF FF 00 
00 00 00 00 00 21 F9 04 04 32 00 00 00 21 FE 0E 
4D 61 64 65 20 77 69 74 68 20 47 49 4D 50 00 2C 
00 00 00 00 10 00 10 00 00 03 96 08 00 10 81 11 
22 22 38 33 03 80 00 11 11 28 22 32 83 33 00 00 
18 11 21 82 22 33 33 08 00 10 81 11 22 22 38 33 
03 80 00 11 11 28 22 32 83 33 00 00 18 11 21 82 
22 33 33 08 00 10 81 11 22 22 38 33 03 80 00 11 
11 28 22 32 83 33 00 00 18 11 21 82 22 33 33 08 
00 10 81 11 22 22 38 33 03 80 00 11 11 28 22 32 
83 33 00 00 18 11 21 82 22 33 33 08 00 10 81 11 
22 22 38 33 03 80 00 11 11 28 22 32 83 33 00 00 
18 11 21 82 22 33 33 08 00 10 81 11 22 22 38 33 
93 00 21 F9 04 05 32 00 06 00 2C 03 00 03 00 0A 
00 0A 00 00 03 3B 48 44 44 84 44 44 44 48 44 44 
84 44 44 44 48 44 44 84 44 44 44 48 44 44 84 44 
44 44 48 54 55 85 55 55 55 58 55 55 85 55 55 55 
58 55 55 85 55 55 55 58 55 55 85 55 55 55 58 55 
95 00 3B                                        
HEX
  $hex =~ tr/0-9A-F//cd;
  return pack("H*", $hex);
}

sub image2 {
  # based on testout/t101.jpg from Imager
  my $hex = <<HEX;
FF D8 FF E0 00 10 4A 46 49 46 00 01 01 00 00 01 
00 01 00 00 FF DB 00 43 00 1B 12 14 17 14 11 1B 
17 16 17 1E 1C 1B 20 28 42 2B 28 25 25 28 51 3A 
3D 30 42 60 55 65 64 5F 55 5D 5B 6A 78 99 81 6A 
71 90 73 5B 5D 85 B5 86 90 9E A3 AB AD AB 67 80 
BC C9 BA A6 C7 99 A8 AB A4 FF DB 00 43 01 1C 1E 
1E 28 23 28 4E 2B 2B 4E A4 6E 5D 6E A4 A4 A4 A4 
A4 A4 A4 A4 A4 A4 A4 A4 A4 A4 A4 A4 A4 A4 A4 A4 
A4 A4 A4 A4 A4 A4 A4 A4 A4 A4 A4 A4 A4 A4 A4 A4 
A4 A4 A4 A4 A4 A4 A4 A4 A4 A4 A4 A4 A4 A4 FF C0 
00 11 08 00 96 00 96 03 01 22 00 02 11 01 03 11 
01 FF C4 00 1F 00 00 01 05 01 01 01 01 01 01 00 
00 00 00 00 00 00 00 01 02 03 04 05 06 07 08 09 
0A 0B FF C4 00 B5 10 00 02 01 03 03 02 04 03 05 
05 04 04 00 00 01 7D 01 02 03 00 04 11 05 12 21 
31 41 06 13 51 61 07 22 71 14 32 81 91 A1 08 23 
42 B1 C1 15 52 D1 F0 24 33 62 72 82 09 0A 16 17 
18 19 1A 25 26 27 28 29 2A 34 35 36 37 38 39 3A 
43 44 45 46 47 48 49 4A 53 54 55 56 57 58 59 5A 
63 64 65 66 67 68 69 6A 73 74 75 76 77 78 79 7A 
83 84 85 86 87 88 89 8A 92 93 94 95 96 97 98 99 
9A A2 A3 A4 A5 A6 A7 A8 A9 AA B2 B3 B4 B5 B6 B7 
B8 B9 BA C2 C3 C4 C5 C6 C7 C8 C9 CA D2 D3 D4 D5 
D6 D7 D8 D9 DA E1 E2 E3 E4 E5 E6 E7 E8 E9 EA F1 
F2 F3 F4 F5 F6 F7 F8 F9 FA FF C4 00 1F 01 00 03 
01 01 01 01 01 01 01 01 01 00 00 00 00 00 00 01 
02 03 04 05 06 07 08 09 0A 0B FF C4 00 B5 11 00 
02 01 02 04 04 03 04 07 05 04 04 00 01 02 77 00 
01 02 03 11 04 05 21 31 06 12 41 51 07 61 71 13 
22 32 81 08 14 42 91 A1 B1 C1 09 23 33 52 F0 15 
62 72 D1 0A 16 24 34 E1 25 F1 17 18 19 1A 26 27 
28 29 2A 35 36 37 38 39 3A 43 44 45 46 47 48 49 
4A 53 54 55 56 57 58 59 5A 63 64 65 66 67 68 69 
6A 73 74 75 76 77 78 79 7A 82 83 84 85 86 87 88 
89 8A 92 93 94 95 96 97 98 99 9A A2 A3 A4 A5 A6 
A7 A8 A9 AA B2 B3 B4 B5 B6 B7 B8 B9 BA C2 C3 C4 
C5 C6 C7 C8 C9 CA D2 D3 D4 D5 D6 D7 D8 D9 DA E2 
E3 E4 E5 E6 E7 E8 E9 EA F2 F3 F4 F5 F6 F7 F8 F9 
FA FF DA 00 0C 03 01 00 02 11 03 11 00 3F 00 E6 
68 A2 8A 00 28 A2 8A 00 28 A2 8A 00 28 A2 8A 00 
28 A2 8A 00 28 A2 8A 00 28 A2 8A 00 28 A2 8A 00 
28 A2 8A 00 28 A2 8A 00 28 A2 8A 00 28 A9 22 00 
F5 A7 ED 1E 95 D9 4B 08 EA 47 99 32 5C AC 41 45 
4F B4 7A 51 B4 7A 56 9F 51 97 71 73 10 51 53 ED 
1E 94 6D 1E 94 7D 46 5D C3 98 82 8A 9F 68 F4 A5 
0A 33 D2 8F A8 CB B8 73 10 60 FA 51 83 E8 6B A1 
B7 B6 84 C2 A4 A0 CE 3D 2A 4F B2 C1 FF 00 3C C7 
E5 5E 34 B1 0A 32 6A C7 2B C5 C5 3B 58 E6 B0 7D 
0D 18 3E 86 BA 5F B2 C1 FF 00 3C C7 E5 47 D9 60 
FF 00 9E 63 F2 A9 FA D2 EC 1F 5C 8F 63 9A C1 F4 
34 60 FA 1A E9 7E CB 07 FC F3 1F 95 1F 65 83 FE 
79 8F CA 8F AD 2E C1 F5 C8 F6 39 9A 2A F6 AD 1A 
C7 38 08 00 18 AA 35 D3 19 73 2B 9D 70 97 3C 54 
82 8A 28 AA 28 28 A2 8A 00 92 2E F5 2D 45 17 7A 
96 BD BC 2F F0 91 94 B7 0A 28 A2 BA 44 14 51 40 
04 F4 A2 F6 0D C2 81 D6 9E 22 63 DA 9D E4 35 73 
CB 13 4A 3A 39 1B 2C 3D 56 AE A2 6C DB 7F A8 4F 
A5 4B 50 5B 48 82 25 52 79 02 A7 EB 5F 1F 57 E3 
6C F1 6A D3 9C 24 D4 95 82 8A 28 AC CC C2 8A 28 
A0 0C 4D 67 FE 3E 07 D2 B3 AB 47 59 FF 00 8F 81 
F4 AC EA F4 E9 7C 08 F6 28 7F 0D 05 14 51 5A 9B 
05 14 51 40 12 45 DE A5 A8 A2 EF 52 D7 B7 85 FE 
12 32 96 E1 45 14 01 93 8A E9 7A 0B 71 C8 85 CD 
59 48 C2 8A 23 5D AB 4F AF 9D C5 E2 E5 56 4E 31 
7A 1E F6 1B 0D 1A 71 BB DC 28 A2 8A E1 3B 02 A6 
86 E1 90 E0 F2 2A 1A 29 34 9E E6 55 68 C2 B4 79 
66 AE 6A 2B 07 19 14 B5 4A D2 5D AD B4 F4 35 76 
B9 A5 1E 56 7C 6E 33 0C F0 D5 5C 3A 74 0A 28 A2 
A4 E4 31 35 9F F8 F8 1F 4A CE AD 1D 67 FE 3E 07 
D2 B3 AB D3 A5 F0 23 D8 A1 FC 34 14 51 45 6A 6C 
14 51 45 00 49 17 7A 96 A2 8B BD 4B 5E DE 17 F8 
48 CA 5B 85 3E 11 97 14 CA 96 DF EF D3 C4 C9 C6 
94 9A 36 C3 A4 EA C5 32 CD 14 51 5F 2E 7D 18 51 
45 14 00 51 45 14 00 A8 70 C0 D6 9A 1C A8 35 97 
5A 50 FF 00 AB 5F A5 63 54 F0 33 B8 AE 58 C8 7D 
14 51 58 9F 38 62 6B 3F F1 F0 3E 95 9D 5A 3A CF 
FC 7C 0F A5 67 57 A7 4B E0 47 B1 43 F8 68 28 A2 
8A D4 D8 28 A2 8A 00 92 2E F5 2D 45 17 7A 96 BD 
BC 2F F0 91 94 B7 0A 7C 47 0E 29 94 0E 2B 6A 91 
E7 8B 8F 72 A1 2E 59 29 17 69 6A 38 9F 72 FB D4 
95 F2 B5 20 E1 27 16 7D 24 26 A7 15 24 14 51 45 
41 61 45 14 50 02 A0 DC E0 56 9A 8C 28 15 56 D2 
2E 77 9A B7 5C F5 1D DD 8F 95 CD F1 0A A5 45 08 
F4 0A 28 A2 B3 3C 73 13 59 FF 00 8F 81 F4 AC EA 
D1 D6 7F E3 E0 7D 2B 3A BD 3A 5F 02 3D 8A 1F C3 
41 45 14 56 A6 C1 45 14 50 04 91 77 A9 6A 28 BB 
D4 B5 ED E1 7F 84 8C A5 B8 51 45 15 D2 21 55 8A 
9C 8A B2 92 86 EB C1 AA B4 57 2E 23 0B 0A DB EE 
74 D0 C4 CE 8E DB 17 73 4B 54 C3 B0 E8 69 44 AF 
9E B5 E6 4B 2C A8 9E 8C F4 16 61 0B 6A 8B 61 49 
E8 2A CC 36 C4 9C BD 4D 6C A3 C9 53 8E 48 A9 AB 
C6 A9 36 9B 89 E4 E2 73 79 CD 38 D3 56 10 00 06 
05 2D 14 56 27 88 DD F5 61 45 14 50 06 26 B3 FF 
00 1F 03 E9 59 D5 A3 AC FF 00 C7 C0 FA 56 75 7A 
74 BE 04 7B 14 3F 86 82 8A 28 AD 4D 82 8A 28 A0 
09 22 EF 52 D4 31 B0 1D 6A 4D EB 5E C6 1A A4 23 
49 26 CC E4 B5 1D 45 37 7A D1 BD 6B A3 DB 53 EE 
2B 31 D4 53 77 AD 1B D6 8F 6D 4F B8 59 8E A0 75 
A6 EF 5A 04 8B 9A 5E DA 9F 70 B3 3A 0B 6F F5 09 
F4 A9 6A 84 17 F0 2C 4A A5 B9 02 A4 FE D1 B7 FE 
F5 7C 7D 58 49 CD B4 BA 9E 5C A9 4E EF 42 DD 15 
53 FB 46 DF FB D4 7F 68 DB FF 00 7A B3 F6 72 EC 
2F 65 3E C5 BA 2A A7 F6 8D BF F7 A8 FE D1 B7 FE 
F5 1E CE 5D 83 D9 4F B1 9F AC FF 00 C7 C0 FA 56 
75 5C D4 E7 49 E6 0C 87 23 15 4E BD 1A 4A D0 57 
3D 5A 29 A8 24 C2 8A 28 AD 0D 42 8A 28 A0 02 8A 
28 A0 02 8A 28 A0 02 8A 28 A0 02 8A 28 A0 02 8A 
28 A0 02 8A 28 A0 02 8A 28 A0 02 8A 28 A0 02 8A 
28 A0 02 8A 28 A0 02 8A 28 A0 02 8A 28 A0 02 8A 
28 A0 02 8A 28 A0 02 8A 28 A0 02 8A 28 A0 02 8A 
28 A0 02 8A 28 A0 02 8A 28 A0 0F FF D9          
HEX
  $hex =~ tr/0-9A-F//cd;
  return pack("H*", $hex);
}

sub imageg {
  # based on testout/t105_trans.gif from Imager
  my $hex = <<HEX;
47 49 46 38 37 61 14 00 14 00 91 00 00 00 FF 00 
FF 00 00 00 00 00 00 00 00 21 F9 04 01 00 00 02 
00 2C 00 00 00 00 14 00 14 00 00 02 E2 04 08 10 
20 40 80 00 01 02 04 08 10 20 40 80 00 01 02 04 
08 10 20 40 80 11 23 46 8C 18 31 62 C4 88 01 01 
2A 54 A8 50 A1 42 85 0A 15 0A 04 18 31 62 C4 88 
11 23 46 8C 18 10 A0 42 85 0A 15 2A 54 A8 50 A1 
40 80 11 23 46 8C 18 31 62 C4 88 01 01 2A 54 A8 
50 A1 42 85 0A 15 0A 04 18 31 62 C4 88 11 23 46 
8C 18 10 A0 42 85 0A 15 2A 54 A8 50 A1 40 80 11 
23 46 8C 18 31 62 C4 88 01 01 2A 54 A8 50 A1 42 
85 0A 15 0A 04 18 31 62 C4 88 11 23 46 8C 18 10 
A0 42 85 0A 15 2A 54 A8 50 A1 40 80 11 23 46 8C 
18 31 62 C4 88 01 01 2A 54 A8 50 A1 42 85 0A 15 
0A 04 18 31 62 C4 88 11 23 46 8C 18 10 A0 42 85 
0A 15 2A 54 A8 50 A1 40 80 11 23 46 8C 18 31 62 
C4 88 01 01 02 04 08 10 20 40 80 00 01 02 05 00 
3B                                              
HEX
  $hex =~ tr/0-9A-F//cd;
  return pack("H*", $hex);
}

# extract the image tags from the edit page
sub get_images {
  my ($content) = @_;

  require 'HTML/Parser.pm';
  require 'HTML/Entities.pm';

  my @images;

  #my $indent = 0;
  my $in_images;
  my $start = 
    sub {
      my ($tagname, $attr) = @_;

      #print "# "," "x$indent,">$tagname ",join(",", map("$_=>$attr->{$_}", keys %$attr)),"\n";
      #++$indent;
					       
      if ($tagname eq 'td') {
	my $name = $attr->{name};
	#print "# name $name\n" if $name;
	if ($name && $name eq 'images') {
	  ++$in_images;
	}
      }
      elsif ($tagname eq 'img' && $in_images) {
	push @images, { %$attr };
      }
    };
  my $end =
    sub {
      my ($tagname) = @_;

      #--$indent;
      #print "# "," "x$indent,"<$tagname\n";
      
      if ($tagname eq 'td' && $in_images) {
	--$in_images;
      }
    };

  my $p = HTML::Parser->new( start_h => [ $start, "tagname, attr" ],
			     end_h => [ $end, "tagname" ]);
  $p->parse($content);
  $p->eof;
  
  use Data::Dumper;
  my $dump = Dumper \@images;
  $dump =~ s/^/# /gm;
  print $dump;
  
  @images;
}
