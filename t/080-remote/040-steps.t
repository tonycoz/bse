#!perl -w
use strict;
use BSE::Test qw(make_ua base_url);
use JSON;
use DevHelp::HTML;
use Test::More tests => 93;
use Data::Dumper;

my $ua = make_ua;
my $baseurl = base_url;

my $add_url = $baseurl . "/cgi-bin/admin/add.pl";

my @ajax_hdr = qw(X-Requested-With: XMLHttpRequest);

my $parent = do_add({ parentid => -1, title => "parent2" }, "make parent");
sleep 1;
my @kids1;
my @kids2;
for my $num (1..3) {
  push @kids1, 
    do_add({ parentid => $parent->{id}, title => "kid$num"}, "make parent  first kid");
sleep 1;
}

for my $num (1..3) {
  push @kids2,
    do_add({ parentid => $kids1[1]{id}, title => "kid2 - kid $num"}, "make kid2 1 first kid");
  sleep 1;
}

my $base = do_add({ parentid => -1, title => "base" }, "make base article");
sleep 1;

{
  my %add_step =
    (
     add_stepkid => 1,
     id => $parent->{id},
     stepkid => $base->{id},
     _after => $kids1[1]{id},
    );
  my $step_res = do_req($add_url, \%add_step, "add step kid in order");
  ok($step_res->{success}, "add step kid success")
    or diag(Dumper($step_res));

  my %tree_req =
    (
     a_tree => 1,
     id => $parent->{id},
    );
  my $result = do_req($add_url, \%tree_req, "get order");
  ok($result->{success}, "got tree ok");
  my @got_order = map $_->{id}, @{$result->{allkids}};
  my @exp_order = ( $kids1[2]{id}, $kids1[1]{id}, $base->{id}, $kids1[0]{id} );
  is_deeply(\@got_order, \@exp_order, "check kid inserted correctly")
}

{
  my %move_step =
    (
     a_restepkid => 1,
     id => $base->{id},
     parentid => $parent->{id},
     newparentid => $kids1[1]{id},
     _after => $kids2[1]{id},
    );
  my $restep_res = do_req($add_url, \%move_step, "move stepkid in order");
  ok($restep_res->{success}, "restep kid success")
    or diag(Dumper($restep_res));

  {
    # shouldn't be under $parent anymore
    my %tree_req =
      (
       a_tree => 1,
       id => $parent->{id},
      );
    my $result = do_req($add_url, \%tree_req, "get parent order");
    ok($result->{success}, "got tree ok");
    my @got_order = map $_->{id}, @{$result->{allkids}};
    my @exp_order = ( $kids1[2]{id}, $kids1[1]{id}, $kids1[0]{id} );
    is_deeply(\@got_order, \@exp_order, "check kid moved away correctly")
  }
  {
    my %tree_req =
      (
       a_tree => 1,
       id => $kids1[1]->{id},
      );
    my $result = do_req($add_url, \%tree_req, "get kids1[1] order");
    ok($result->{success}, "got tree ok");
    my @got_order = map $_->{id}, @{$result->{allkids}};
    my @exp_order = ( $kids2[2]{id}, $kids2[1]{id}, $base->{id}, $kids2[0]{id} );
    is_deeply(\@got_order, \@exp_order, "check kid inserted correctly")
  }
}

{
  # various error handling checks
  my %base_req =
    (
     a_restepkid => 1,
     id => $base->{id},
    );

  {
    # no parentid
    my $badpar_res = do_req
      ($add_url, { %base_req }, "missing parentid");
    ok(!$badpar_res->{success}, "should fail");
    is($badpar_res->{error_code}, "NOPARENTID", "check error");
  }
  $base_req{parentid} = $kids1[1]{id};
  {
    # invalid parentid
    my $badpar_res = do_req
      ($add_url, { %base_req, parentid => "abc"}, "bad parentid");
    ok(!$badpar_res->{success}, "should fail");
    is($badpar_res->{error_code}, "BADPARENTID", "check error");
  }
  {
    # unknown parentid
    my $badpar_res = do_req
      ($add_url, { %base_req, parentid => 1000+$base->{id}}, "unknown parentid");
    ok(!$badpar_res->{success}, "should fail");
    is($badpar_res->{error_code}, "NOTFOUND", "check error");
  }
  {
    # invalid newparentid
    my $badpar_res = do_req
      ($add_url, { %base_req, newparentid => "abc"}, "bad newparentid");
    ok(!$badpar_res->{success}, "should fail");
    is($badpar_res->{error_code}, "BADNEWPARENT", "check error");
  }
  {
    # unknown newparentid
    my $badpar_res = do_req
      ($add_url, { %base_req, newparentid => 1000+$base->{id}}, "unknown newparentid");
    ok(!$badpar_res->{success}, "should fail");
    is($badpar_res->{error_code}, "UNKNOWNNEWPARENT", "check error");
  }

  {
    # duplicate
    my %add_step =
      (
       add_stepkid => 1,
       id => $parent->{id},
       stepkid => $base->{id},
      );
    my $step_res = do_req($add_url, \%add_step, "add step kid in order");
    ok($step_res->{success}, "add step kid success")
      or diag(Dumper($step_res));

    my $badpar_res = do_req
      ($add_url, { %base_req, newparentid => $parent->{id}}, "duplicate newparentid");
    ok(!$badpar_res->{success}, "should fail");
    is($badpar_res->{error_code}, "NEWPARENTDUP", "check error");
  }
}

for my $art (@kids2, @kids1, $parent, $base) {
  my %del_req =
    (
     remove => 1,
     id => $art->{id},
    );
  my $result = do_req($add_url, \%del_req, "remove $art->{title}");
  ok($result && $result->{success}, "got a remove result")
    or diag(Dumper($result));
}

sub do_req {
  my ($url, $req_data, $comment) = @_;

  my $content = join "&", map "$_=" . escape_uri($req_data->{$_}), keys %$req_data;
  my $req = HTTP::Request->new(POST => $add_url, \@ajax_hdr);

  $req->content($content);
  
  my $resp = $ua->request($req);
  ok($resp->is_success, "$comment successful at http level");
  my $data = eval { from_json($resp->decoded_content) };
  ok($data, "$comment response decoded as json")
    or print "# $@\n";

  return $data;
}

sub do_add {
  my ($req, $comment) = @_;

  $req->{save} = 1;

  my $result = do_req($add_url, $req, $comment);
  my $article;
 SKIP:
  {
    $result or skip("No JSON result", 1);
    if (ok($result->{success} && $result->{article}, "check success and article")) {
      return $result->{article};
    }
  };
  diag(Dumper($result));

  return;
}
