package BSE::Test;
use strict;
use vars qw(@ISA @EXPORT @EXPORT_OK);
@ISA = qw(Exporter);
require 'Exporter.pm';
@EXPORT = qw(base_url ok fetch_ok make_url skip make_ua);
@EXPORT_OK = qw(base_url ok make_ua fetch_url fetch_ok make_url skip 
                make_post check_form post_ok check_content);

my %conf;

my $conffile = $ENV{BSETEST} || 'test.cfg';

open TESTCFG, "< $conffile" or die "Cannot open $conffile: $!";
while (<TESTCFG>) {
  next if /^\s*[\#;]/;
  chomp;
  next unless /^\s*(\w+)\s*=\s*(.*)/;
  $conf{$1} = $2;
}
close TESTCFG;

sub base_url { $conf{base_url} or die "No base_url in test config" }

sub base_securl { 
  $conf{securl} or $conf{base_url} or die "No securl or base_url in $conffile"
}

sub base_dir { $conf{base_dir} or die "No base_dir in test config" }

sub mysql_name { $conf{mysql} or die "No mysql in test config" }

sub test_dsn { $conf{dsn} or die "No dsn in test config" }

sub test_dbuser { $conf{dbuser} or die "No dbuser in test config" }

sub test_dbpass { $conf{dbpass} or die "No dbpass in test config" }

sub test_dbclass { $conf{dbclass} or die "No dbclass in test config" }

sub test_sessionclass { $conf{sessionclass} or die "No sessionclass in config" }

sub test_conffile {
  return $conffile;
}

my $test_num = 1;

sub ok ($$) {
  my ($ok, $desc) = @_;

  if ($ok) {
    print "ok $test_num # $desc\n";
  }
  else {
    print "not ok $test_num # $desc ",join(",", caller()),"\n";
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
  require "WWW/Automate.pm";
  require "HTTP/Cookies.pm";
  my $ua = WWW::Automate->new;
  $ua->cookie_jar(HTTP::Cookies->new);

  $ua;
}

# in scalar context returns content
# in list context returns ($content, $code)
# $post is any data to be part of a post request
sub fetch_url {
  my ($ua, $url, $method, $post) = @_;

  $method ||= 'GET';
  my $hdrs = HTTP::Headers->new;
  $hdrs->header(Content_Length => length $post) if $post;
  my $req = HTTP::Request->new($method, $url, $hdrs);
  $req->content($post) if $post;
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

sub check_content {
  my ($content, $note, $match) = @_;
  unless (ok($content =~ /$match/s, "$note: match")) {
    print "# wanted /$match/ got:\n";
    my $copy = $content;
    $copy =~ s/^/# /gm;
    $copy .= "\n" unless $copy =~ /\n\z/;
    print $copy;
  }
}

sub _check_fetch {
  my ($content, $code, $ok, $headers,
      $note, $match, $headmatch) = @_;  

  my $good = $ok;
  ok($ok, "$note: fetch ($code)");
  if ($ok) {
    if ($match) {
      unless (ok($content =~ /$match/s, "$note: match")) {
	print "# wanted /$match/ got:\n";
	my $copy = $content;
	$copy =~ s/^/# /gm;
	$copy .= "\n" unless $copy =~ /\n\z/;
	print $copy;
	$good = 0;
      }
    }
    if ($headmatch) {
      unless (ok($headers =~ /$headmatch/s, "$note: headmatch")) {
	print "# wanted /$headmatch/ got:\n";
	my $copy = $headers;
	$copy =~ s/^/# /gm;
	$copy .= "\n" unless $copy =~ /\n\z/;
	print $copy;
	$good = 0;
      }
    }
  }
  else {
    my $count = 0;
    $count++ if $match;
    $count++ if $headmatch;
    skip("$note: fetch failed", $count) if $count;
  }

  if (wantarray) {
    return ($content, $code, $good, $headers);
  }
  else {
    return $good ? $content : undef;
  }
}

sub make_post {
  my (@data) = @_;

  require "URI/Escape.pm";
  my @pairs;
  while (my ($key, $value) = splice(@data, 0, 2)) {
    push(@pairs, "$key=".URI::Escape::uri_escape($value));
  }
  return join("&",@pairs);
}

sub post_ok {
  my ($ua, $note, $url, $data, $match, $headmatch) = @_;

  $data = make_post(@$data) if ref $data;

  my ($content, $code, $ok, $headers) = fetch_url($ua, $url, POST=>$data);

  return _check_fetch($content, $code, $ok, $headers,
		      $note, $match, $headmatch)
}

sub fetch_ok {
  my ($ua, $note, $url, $match, $headmatch) = @_;

  my $ok = $ua->get($url);
  return _check_fetch($ua->{content}, $ua->{status}, $ok, 
		      $ua->{res}->headers_as_string, $note, 
		      $match, $headmatch)
}

sub check_form {
  my ($content, $note, %checks) = @_;

  require 'HTML/Parser.pm';
  require 'HTML/Entities.pm';
  my $in;
  my $keep;
  my $saved = '';
  my %todo = %checks;
  my $inselect;
  my $selname;
  my $checked_sel_value;
  my $textname;
  my %values;

  my $text =
    sub {
      my ($t) = @_;
      $saved .= $t if $keep;
    };
  my $start = 
    sub {
      my ($tagname, $attr) = @_;

      if ($tagname eq 'input') {
	my $name = $attr->{name};
	if ($name && $todo{$name}) {
	  ok(1, "$note - $name - field is present");
	  $values{$name} = $attr->{$name};
	  if (defined $todo{$name}[0]) {
	    my $cvalue = $checks{$name}[0];
	    my $fvalue = $attr->{value};
	    if (defined $fvalue) {
	      ok($cvalue eq $fvalue, "$note - $name - comparing values");
	    }
	    else {
	      ok(0, "$note - $name - value is not present");
	    }
	  }
	  if (defined $todo{$name}[1]) {
	    my $ttype = $todo{$name}[1];
	    my $ftype = $attr->{type};
	    if (defined $ftype) {
	      ok($ttype eq $ftype, "$note - $name - comparing types");
	    }
	    else {
	      ok(0, "$note - $name - type not present");
	    }
	  }
	  delete $todo{$name};
	}
      }
      elsif ($tagname eq 'select') {
	$selname = $attr->{name};
	
	if ($todo{$selname}) {
	  ok(1, "$note - $selname - field is present");
	  $inselect = 1;
	  if (defined $todo{$selname}[1]) {
	    $checked_sel_value = 0;
	    my $ttype = $todo{$selname}[1];
	    ok ($ttype eq 'select', "$note - $selname - checking type (select)");
	  }
	}
      }
      elsif ($tagname eq 'option' && $inselect) {
	unless (exists $attr->{value}) {
	  print "# warning - option in select $selname missing value\n";
	}
	if (exists $attr->{selected}) {
	  $checked_sel_value = 1;
	  $values{$selname} = $attr->{value};
	  if (defined $todo{$selname}[0]) {
	    my $fvalue = $attr->{value};
	    my $tvalue = $todo{$selname}[0];
	    if (defined $fvalue) {
	      ok($fvalue eq $tvalue, "$note - $selname - checking value ($fvalue vs $tvalue)");
	    }
	    else {
	      ok(0, "$note - $selname - no value supplied");
	    }
	  }
	}
      }
      elsif ($tagname eq 'textarea') {
	$textname = $attr->{name};
	$saved = '';
	++$keep;
      }
    };
  my $end =
    sub {
      my ($tagname) = @_;

      if ($tagname eq 'select' && $inselect) {
	if (!$checked_sel_value) {
	  ok(0, "$note - $selname - no value selected");
	}
	delete $todo{$selname};
      }
      elsif ($tagname eq 'textarea') {
	$keep = 0;
	if ($todo{$textname}) {
	  my $fvalue = HTML::Entities::decode_entities($saved);
	  $values{$textname} = $fvalue;
	  ok(1, "$note - $textname - field exists");
	  if (defined $todo{$textname}[0]) {
	    my $tvalue = $todo{$textname}[0];
	    ok($tvalue eq $fvalue, "$note - $textname - checking value($tvalue vs $fvalue)");
	  }
	  if (defined $todo{$textname}[1]) {
	    ok ($todo{$textname}[1] eq 'textarea',
		"$note - $textname - check field type");
	  }
	  delete $todo{$textname};
	}
      }
    };
  my $p = HTML::Parser->new( text_h => [ $text, "dtext" ],
			     start_h => [ $start, "tagname, attr" ],
			     end_h => [ $end, "tagname" ]);
  $p->parse($content);
  $p->eof;
  for my $name (keys %todo) {
    ok(0, "$note - $name - field doesn't exist");
    my $count = 0;
    ++$count if defined $todo{$name}[0];
    ++$count if defined $todo{$name}[1];
    skip("$note - $name - no field", $count);
  }

  return %values;
}

1;

