package BSE::Test;
use strict;
use vars qw(@ISA @EXPORT @EXPORT_OK);
@ISA = qw(Exporter);
require 'Exporter.pm';
@EXPORT = qw(base_url ok fetch_ok make_url skip make_ua);
@EXPORT_OK = qw(base_url ok make_ua fetch_url fetch_ok make_url skip);

my %conf;

open TESTCFG, "< test.cfg" or die "Cannot open test.cfg: $!";
while (<TESTCFG>) {
  next if /^\s*[\#;]/;
  chomp;
  next unless /^\s*(\w+)\s*=\s*(.*)/;
  $conf{$1} = $2;
}
close TESTCFG;

sub base_url { $conf{base_url} or die "No base_url in test config" }

my $test_num = 1;

sub ok ($$) {
  my ($ok, $desc) = @_;

  if ($ok) {
    print "ok $test_num # $desc\n";
  }
  else {
    print "not ok $test_num # desc ",join(",", caller()),"\n";
  }
  ++$test_num;
  return $ok;
}

sub skip {
  my ($desc, $count) = @_;

  $count ||= 1;
  for my $i (1..$count) {
    print "ok $test_num # skipped: $desc\n";
    ++$test_num;
  }
}

sub make_ua {
  require "LWP/UserAgent.pm";
  require "HTTP/Cookies.pm";
  my $ua = LWP::UserAgent->new;
  $ua->cookie_jar(HTTP::Cookies->new);

  $ua;
}

# in scalar context returns content
# in list context returns ($content, $code)
# $post is any data to be part of a post request
sub fetch_url {
  my ($ua, $url, $method, $post) = @_;

  $method ||= 'GET';
  my $req = HTTP::Request->new($method, $url);
  if ($post) {
    $req->content($post);
  }
  my $resp = $ua->request($req);
  if (wantarray) {
    return ($resp->content(), $resp->code(), $resp->is_success, 
	    $resp->headers_as_string());
  }
  else {
    return $resp->is_success() ? $resp->content() : undef;
  }
}

sub make_url {
  my ($base, @data) = @_;

  require "URI/Escape.pm";
  my @pairs;
  while (my ($key, $value) = splice(@data, 0, 2)) {
    push(@pairs, "$key=".URI::uri_escape($value));
  }
  return $base."?".join("&",@pairs);
}

sub fetch_ok {
  my ($ua, $note, $url, $match, $headmatch) = @_;

  my ($content, $code, $ok, $headers) = fetch_url($ua, $url);

  ok($ok, "$note: fetch ($code)");
  if ($ok) {
    if ($match) {
      unless (ok($content =~ /$match/s, "$note: match")) {
	print "# wanted /$match/ got:\n";
	my $copy = $content;
	$copy =~ s/^/# /gm;
	$copy .= "\n" unless $copy =~ /\n\z/;
	print $copy;
      }
    }
    if ($headmatch) {
      unless (ok($headers =~ /$headmatch/s, "$note: headmatch")) {
	print "# wanted /$headmatch/ got:\n";
	my $copy = $headers;
	$copy =~ s/^/# /gm;
	$copy .= "\n" unless $copy =~ /\n\z/;
	print $copy;
      }
    }
  }
  else {
    my $count = 0;
    $count++ if $match;
    $count++ if $headmatch;
    skip("$note: fetch failed", $count) if $count;
  }
}

1;

