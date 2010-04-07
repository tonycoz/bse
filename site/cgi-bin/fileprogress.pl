#!/usr/bin/perl -w
# -d:ptkdb
BEGIN { $ENV{DISPLAY} = '192.168.32.15:0.0' }
use strict;
use FindBin;
use lib "$FindBin::Bin/modules";
use BSE::Request;
use BSE::Template;

my $req = BSE::Request->new(nosession => 1);

my $cgi = $req->cgi;
my $key = $cgi->param("_upload");
my $result;
if ($key) {
  my $cached = $req->cache_get("upload-$key");
  if ($cached) {
    $result =
      {
       success => 1,
       progress => $cached,
      };
  }
  else {
    $result =
      {
       success => 1,
       progress => [],
      };
  }
}
else {
  $result =
    {
     success => 0,
     message => "missing _upload parameter",
    };
}

BSE::Template->output_result($req, $req->json_content($result));
