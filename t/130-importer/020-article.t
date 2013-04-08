#!perl -w
use strict;
use BSE::Test qw(base_url);
use File::Spec;
use File::Temp;

use Test::More tests => 42;

BEGIN {
  unshift @INC, File::Spec->catdir(BSE::Test::base_dir(), "cgi-bin", "modules");
}

use BSE::Importer;
use BSE::API qw(bse_init bse_make_article);

my $base_cgi = File::Spec->catdir(BSE::Test::base_dir(), "cgi-bin");
ok(bse_init($base_cgi),   "initialize api")
  or print "# failed to bse_init in $base_cgi\n";

my $when = time;

my $cfg = BSE::Cfg->new(path => $base_cgi, extra_text => <<CFG);
[import profile simple$when]
map_title=1
source=CSV
target=Article

[import profile simpleupdate$when]
map_linkAlias=1
map_body=2
map_file1_file=3
map_image1_file=4
source=CSV
target=Article
update_only=1
sep_char=\\t
file_path=t
ignore_missing=0

[import profile completefile$when]
map_linkAlias=1
map_file1_file=2
map_file1_name=3
map_file1_displayName=4
map_file1_storage=5
map_file1_description=6
map_file1_forSale=7
map_file1_download=8
map_file1_requireUser=9
map_file1_notes=10
map_file1_hide_from_list=11
skiplines=0
file_path=t
ignore_missing=0
update_only=1
source=CSV
target=Article

[import profile updatefile$when]
map_linkAlias=1
map_file1_name=2
map_file1_description=3
skiplines=0
file_path=t
ignore_missing=0
update_only=1
source=CSV
target=Article

[import profile updatefileb$when]
map_linkAlias=1
map_file1_name=2
map_file1_file=3
skiplines=0
file_path=t/data
ignore_missing=0
update_only=1
source=CSV
target=Article

[import profile newdup$when]
map_linkAlias=1
map_title=2
skiplines=0
source=CSV
target=Article

CFG

{
  my @added;

  my $imp = BSE::Importer->new(cfg => $cfg, profile => "simple$when", callback => sub { note @_ });
  $imp->process("t/data/importer/article-simple.csv");
  @added = sort { $a->title cmp $b->title } $imp->leaves;

  is(@added, 2, "imported two articles");
  is($added[0]->title, "test1", "check title of first import");
  is($added[1]->title, "test2", "check title of second import");

  END {
    $_->remove($cfg) for @added;
  }
}

{
  my $testa = bse_make_article(cfg => $cfg, title => "test updates",
			       linkAlias => "alias$when");

  {
    my $fh = File::Temp->new;
    my $filename = $fh->filename;
    print $fh <<EOS;
linkAlias\tbody\tfile1_file\timage1_file
"alias$when"\t"This is the body text with multiple lines

Yes, multiple lines with CSV!"\tt00smoke.t\tdata/t101.jpg
EOS
    close $fh;
    my $imp = BSE::Importer->new(cfg => $cfg, profile => "simpleupdate$when", callback => sub { note @_ });
    $imp->process($filename);
    my $testb = Articles->getByPkey($testa->id);
    like($testb->body, qr/This is the body/, "check the body is updated");
    my @images = $testb->images;
    is(@images, 1, "have an image");
    like($images[0]->image, qr/t101\.jpg/, "check file name");
    is(-s $images[0]->full_filename, -s "t/data/t101.jpg",
       "check size matches source");

    my @files = $testb->files;
    is(@files, 1, "should be 1 file");
    is($files[0]->displayName, "t00smoke.t", "check display name");
    is(-s $files[0]->full_filename, -s "t/t00smoke.t", "check size");
  }

 SKIP:
  {
    my $fh = File::Temp->new;
    my $filename = $fh->filename;
    print $fh <<EOS;
"alias$when",t00smoke.t,test,"A Test File.txt",local,"A test file from BSE",1,1,1,"Some Notes",1
EOS
    close $fh;
    my $imp = BSE::Importer->new(cfg => $cfg, profile => "completefile$when", callback => sub { note @_ });
    $imp->process($filename);
    my $testb = Articles->getByPkey($testa->id);

    my ($file) = grep $_->name eq "test", $testb->files;
    ok($file, "found the file with name 'test'")
      or skip "File not found", 9;
    is(-s $file->full_filename, -s "t/t00smoke.t", "check size");
    is($file->displayName, "A Test File.txt", "displayName");
    is($file->storage, "local", "storage");
    is($file->description, "A test file from BSE", "description");
    is($file->forSale, 1, "forSale");
    is($file->download, 1, "download");
    is($file->requireUser, 1, "requireUser");
    is($file->notes, "Some Notes", "notes");
    is($file->hide_from_list, 1, "hide_from_list");
  }

 SKIP:
  {
    my $fh = File::Temp->new;
    my $filename = $fh->filename;
    print $fh <<EOS;
"alias$when",test,"New description"
EOS
    close $fh;
    my $imp = BSE::Importer->new(cfg => $cfg, profile => "updatefile$when", callback => sub { note @_ });
    $imp->process($filename);
    my $testb = Articles->getByPkey($testa->id);

    my ($file) = grep $_->name eq "test", $testb->files;
    ok($file, "found the updated file with name 'test'")
      or skip "File not found", 9;
    is($file->description, "New description", "description");
    # other fields should be unchanged
    is(-s $file->full_filename, -s "t/t00smoke.t", "check size");
    is($file->displayName, "A Test File.txt", "displayName");
    is($file->storage, "local", "storage");
    is($file->forSale, 1, "forSale");
    is($file->download, 1, "download");
    is($file->requireUser, 1, "requireUser");
    is($file->notes, "Some Notes", "notes");
    is($file->hide_from_list, 1, "hide_from_list");
  }

 SKIP:
  {
    my $fh = File::Temp->new;
    my $filename = $fh->filename;
    print $fh <<EOS;
"alias$when",test,t101.jpg
EOS
    close $fh;
    my $imp = BSE::Importer->new(cfg => $cfg, profile => "updatefileb$when", callback => sub { note @_ });
    $imp->process($filename);
    my $testb = Articles->getByPkey($testa->id);

    my ($file) = grep $_->name eq "test", $testb->files;
    ok($file, "found the updated file with name 'test'")
      or skip "File not found", 9;
    is(-s $file->full_filename, -s "t/data/t101.jpg", "check size");
    is($file->displayName, "t101.jpg", "new displayName");
    # other fields should be unchanged
    is($file->storage, "local", "storage");
    is($file->description, "New description", "description");
    is($file->forSale, 1, "forSale");
    is($file->download, 1, "download");
    is($file->requireUser, 1, "requireUser");
    is($file->notes, "Some Notes", "notes");
    is($file->hide_from_list, 1, "hide_from_list");
  }

  { # fail to duplicate a link alias
    my $fh = File::Temp->new;
    my $filename = $fh->filename;
    my $id = $testa->id;
    print $fh <<EOS;
"alias$when",test,t101.jpg
EOS
    close $fh;
    my $imp = BSE::Importer->new(cfg => $cfg, profile => "newdup$when", callback => sub { note @_ });
    $imp->process($filename);
    is_deeply([ $imp->leaves ], [], "should be no updated articles");
  }

  END {
    $testa->remove($cfg) if $testa;
  }
}
