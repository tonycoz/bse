#!perl -w
use strict;
use BSE::Test ();
use BSE::Cfg;
use BSE::API qw(bse_init bse_cfg);
use BSE::Util::Fetcher;

use Test::More;

my $base_cgi = File::Spec->catdir(BSE::Test::base_dir(), "cgi-bin");
BSE::API::bse_init($base_cgi);
my $cfg = bse_cfg();

my $art = BSE::API::bse_make_article
  (
   cfg => $cfg,
   title => "010-fetcher.t",
  );

my $html = $cfg->entryVar("paths", "public_html");

my $base_cfg = <<EOS;
[basic]
access_control=1

[paths]
public_html=$html

EOS

note "article ". $art->id;

SKIP:
{
  my $wcfg = BSE::Cfg->new_from_text(text => <<EOS);
$base_cfg

[automatic data]
data_test=test
EOS

  my $url_meta = $art->add_meta
    (
     value => "http://test.develop-help.com/test.json",
     name => "test_url",
     content_type => "text/plain",
    );
  ok($url_meta, "add url metadata");

  my $f = BSE::Util::Fetcher->new
    (
     cfg => $wcfg,
     save => 1,
     log => 0,
     section => "automatic data",
     articles => [ $art->id ],
    );
  ok($f->run(), "do the fetch")
    or do { diag "@$_" for @{$f->errors}; skip "No data", 1 };

  my $meta = $art->meta_by_name("test");
  ok($meta, "data stored in meta")
    or skip "no data stored", 1;
  like($meta->value, qr/\A\[\s+5\s+\]\s+\z/, "check content")
    or skip "wrong data stored", 1;
  is($meta->content_type, "application/json",
     "check content type");
  my $data = $meta->retrieve_json;
  ok($data, "decoded json")
    or skip "No decoded data to look at", 1;
  is($data->[0], 5, "check stored data");

  $url_meta->remove;
  $meta->remove;

  $url_meta = $art->add_meta
    (
     value => "http://test.develop-help.com/test-not.json",
     name => "test_url",
     content_type => "text/plain",
    );
  ok($url_meta, "add invalid json metadata url");
  ok(!$f->run(), "do the fetch");
  $meta = $art->meta_by_name("test");
  ok(!$meta, "should be no data");
  my @msgs = map $_->[1], @{$f->{errors}};
  ok(grep(/^Content failed JSON validation/, @msgs),
     "check json validation failed");
}

SKIP:
{
  my $badcfg = BSE::Cfg->new_from_text(text => <<EOS);
$base_cfg

[automatic data]
data_test=test*
url_test=other*
url_pattern_test=foo
types_test=(
validate_test=unknown
max_length_test=x
on_fail_test=foo
on_success_test=x
EOS

  my $f = BSE::Util::Fetcher->new
    (
     cfg => $badcfg,
     save => 1,
     log => 0,
     section => "automatic data",
     articles => [ $art->id ],
    );
  ok(!$f->run(), "do the fetch (and fail)")
    or skip "It didn't fail", 1;
  my @errors = @{$f->errors};
  my @msgs = map $_->[1], @errors;
  ok(grep(/Invalid metadata name 'test\*'/, @msgs),
     "Invalid name errored");
  ok(grep(/Invalid metadata url 'other\*'/, @msgs),
     "Invalid url errored");
  ok(grep(/Invalid url pattern 'foo'/, @msgs),
     "Invalid url_pattern errored");
  ok(grep(/Cannot compile regexp \/\(\/ for/, @msgs),
     "Invalid test re errored");
  ok(grep(/Invalid validate 'unknown'/, @msgs),
     "Invalid validate errored");
  ok(grep(/Invalid max_length 'x'/, @msgs),
     "Invalid max length errored");
  ok(grep(/Invalid on_fail 'foo'/, @msgs),
     "Invalid on_fail errored");
  ok(grep(/Invalid on_success 'x'/, @msgs),
     "Invalid on_success errored");
}

END {
  $art->remove($cfg);
}

done_testing();
