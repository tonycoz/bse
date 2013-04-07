package BSE::Test;
use strict;
use vars qw(@ISA @EXPORT @EXPORT_OK);
use Exporter 'import';
@EXPORT = qw(base_url fetch_ok make_url skip make_ua);
@EXPORT_OK = qw(base_url make_ua fetch_url fetch_ok make_url skip 
                make_post check_form post_ok check_content follow_ok
                follow_refresh_ok click_ok config test_actions);
use lib 'site/cgi-bin/modules';
use BSE::Cfg;

my $conffile = $ENV{BSETEST} || 'install.cfg';

my $cfg = BSE::Cfg->new
  (
   path => "site/cgi-bin",
   extra_file => $conffile,
  );

sub config {
  $cfg;
}

sub base_url {
  $cfg->entryVar("site", "url");
}

sub base_securl {
  $cfg->entryVar("site", "secureurl");
}

sub base_dir {
  $cfg->entryVar("paths", "siteroot");
}

sub mysql_name {
  $cfg->entry("binaries", "mysql", "mysql");
}

sub test_dsn {
  $cfg->entry("db", "dsn");
}

sub test_dbuser {
  $cfg->entry("db", "user");
}

sub test_dbpass {
  $cfg->entry("db", "password");
}

sub test_dbclass {
  $cfg->entry("db", "class", "BSE::DB::Mysql");
}

sub test_sessionclass {
  $cfg->entry("basic", "session_class", "Apache::Session::Mysql");
}

sub test_perl {
  $cfg->entry("paths", "perl", $^X);
}

sub test_conffile {
  $conffile;
}

sub make_ua {
  require WWW::Mechanize;
  require "HTTP/Cookies.pm";
  my $ua = WWW::Mechanize->new(onerror => undef);
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
  my $tb = Test::Builder->new;
  local $Test::Builder::Level = $Test::Builder::Level + 1;

  return $tb->like($content, qr/$match/s, "$note: match");
}

sub _check_fetch {
  my ($content, $code, $ok, $headers,
      $note, $match, $headmatch) = @_;  

  my $tb = Test::Builder->new;
  local $Test::Builder::Level = $Test::Builder::Level + 1;

  my $good = $ok;
  $tb->ok($ok, "$note: fetch ($code)");
  SKIP:
  {
    my $count = 0;
    $count++ if $match;
    $count++ if $headmatch;
    $ok or skip("$note: fetch failed", $count) if $count;
    if ($match) {
      unless ($tb->like($content, qr/$match/s, "$note: match")) {
	#print "# wanted /$match/ got:\n";
	#my $copy = $content;
	#$copy =~ s/^/# /gm;
	#$copy .= "\n" unless $copy =~ /\n\z/;
	#print $copy;
	$good = 0;
      }
    }
    if ($headmatch) {
      unless ($tb->like($headers, qr/$headmatch/s, "$note: headmatch")) {
	#print "# wanted /$headmatch/ got:\n";
	#my $copy = $headers;
	#$copy =~ s/^/# /gm;
	#$copy .= "\n" unless $copy =~ /\n\z/;
	#print $copy;
	$good = 0;
      }
    }
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

  my $resp = $ua->get($url);
  my $ok = $resp->is_success;
  return _check_fetch($ua->{content}, $ua->{status}, $ok, 
		      $ua->{res}->headers_as_string, $note, 
		      $match, $headmatch)
}

sub follow_ok {
  my ($ua, $note, $link, $match, $headmatch) = @_;

  my $ok;
  if (ref $link) {
    my $resp = $ua->follow_link(%$link);
    $ok = $resp->is_success;
  }
  else {
    $ok = $ua->follow_link(text_regex => qr/\Q$link/);
  }

  return _check_fetch($ua->{content}, $ua->{status}, $ok, 
		      $ua->{res}->headers_as_string, $note, 
		      $match, $headmatch)
}

sub follow_refresh_ok {
  my ($ua, $note, $match, $headmatch) = @_;

  my $skip = 1;
  ++$skip if $match;
  ++$headmatch if $headmatch;
  my $refresh = $ua->response->header('Refresh');
  if (ok($refresh, "$note - refresh header")) {
    my $url;
    if ($refresh =~ /^\s*\d+\s*;\s*url=\"([^\"]+)\"/
       or $refresh =~ /^\s*\d+\s*;\s*url\s*=\s*(\S+)/) {
      $url = $1;
      $url = URI->new_abs($url, $ua->uri);
    }
    else {
      $url = $ua->uri;
    }
    print "# refresh to $url\n";
    fetch_ok($ua, "$note - fetch", $url);
  }
  else {
    skip("$note - skipped, not a refresh", $skip);
  }
}

sub click_ok {
  my ($ua, $note, $name, $match, $headmatch) = @_;

  local $Test::Builder::Level = $Test::Builder::Level + 1;
  my $tb = Test::Builder->new;

  my $ok = $tb->ok($ua->click($name), "$note - click");
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

  my $tb = Test::Builder->new;
  local $Test::Builder::Level = $Test::Builder::Level + 1;

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
	  $tb->ok(1, "$note - $name - field is present");
	  $values{$name} = $attr->{$name};
	  if (defined $todo{$name}[0]) {
	    my $cvalue = $checks{$name}[0];
	    my $fvalue = $attr->{value};
	    if (defined $fvalue) {
	      $tb->ok($cvalue eq $fvalue, "$note - $name - comparing values");
	    }
	    else {
	      $tb->ok(0, "$note - $name - value is not present");
	    }
	  }
	  if (defined $todo{$name}[1]) {
	    my $ttype = $todo{$name}[1];
	    my $ftype = $attr->{type};
	    if (defined $ftype) {
	      $tb->ok($ttype eq $ftype, "$note - $name - comparing types");
	    }
	    else {
	      $tb->ok(0, "$note - $name - type not present");
	    }
	  }
	  delete $todo{$name};
	}
      }
      elsif ($tagname eq 'select') {
	$selname = $attr->{name};
	
	if ($todo{$selname}) {
	  $tb->ok(1, "$note - $selname - field is present");
	  $inselect = 1;
	  if (defined $todo{$selname}[1]) {
	    $checked_sel_value = 0;
	    my $ttype = $todo{$selname}[1];
	    $tb->ok ($ttype eq 'select', "$note - $selname - checking type (select)");
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
	      $tb->ok($fvalue eq $tvalue, "$note - $selname - checking value ($fvalue vs $tvalue)");
	    }
	    else {
	      $tb->ok(0, "$note - $selname - no value supplied");
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
	  $tb->ok(0, "$note - $selname - no value selected");
	}
	delete $todo{$selname};
      }
      elsif ($tagname eq 'textarea') {
	$keep = 0;
	if ($todo{$textname}) {
	  my $fvalue = HTML::Entities::decode_entities($saved);
	  $values{$textname} = $fvalue;
	  $tb->ok(1, "$note - $textname - field exists");
	  if (defined $todo{$textname}[0]) {
	    my $tvalue = $todo{$textname}[0];
	    $tb->ok($tvalue eq $fvalue, "$note - $textname - checking value($tvalue vs $fvalue)");
	  }
	  if (defined $todo{$textname}[1]) {
	    $tb->ok ($todo{$textname}[1] eq 'textarea',
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
    $tb->ok(0, "$note - $name - field doesn't exist");
    my $count = 0;
    ++$count if defined $todo{$name}[0];
    ++$count if defined $todo{$name}[1];
  SKIP: {
      skip("$note - $name - no field", $count) if $count;
    }
  }

  return %values;
}

# test that all actions have methods for a given dispatcher class
sub test_actions {
  my ($class) = @_;

  my $tb = Test::Builder->new;
  local $Test::Builder::Level = $Test::Builder::Level + 1;

  my $obj = $class->new;
  my $actions = $obj->actions;
  my @bad;
  for my $action (sort keys %$actions) {
    my $method = "req_$action";
    unless ($obj->can($method)) {
      push @bad, $action;
    }
  }
  $tb->ok(!@bad, "check all actions have a method for $class");
  print STDERR "No method found for $class action $_\n" for @bad;

  return !@bad;
}

1;

