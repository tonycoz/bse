#!/usr/bin/perl -w
# -d:ptkdb
BEGIN { $ENV{DISPLAY} = '192.168.32.15:0.0' }
use strict;
use FindBin;
use lib "$FindBin::Bin/../modules";
use BSE::Request;
use BSE::Template;
use BSE::ChangePW;

my $req = BSE::Request->new;

my $result;
if ($req->check_admin_logon()) {
  if ($req->user) {
    $result = BSE::ChangePW->dispatch($req);
  }
  else {
    $result = BSE::Template->
      get_refresh($req->url(menu => { 'm' => "Security not enabled" }),
		  $req->cfg);
  }
}
else {
  $result = BSE::Template->get_refresh($req->url('logon'), $req->cfg);
}

$req->output_result($result);
