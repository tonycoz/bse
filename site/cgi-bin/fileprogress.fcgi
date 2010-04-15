#!/usr/bin/perl -w
# -d:ptkdb
BEGIN { $ENV{DISPLAY} = '192.168.32.54:0.0' }
use strict;
use FindBin;
use CGI::Fast;
use lib "$FindBin::Bin/modules";
use BSE::Request;
use BSE::Template;
use BSE::UI::FileProgress;

my $cfg = BSE::Cfg->new; # only do this once

while (my $cgi = CGI::Fast->new) {
  my $req = BSE::Request->new
      (
       nosession => 1,
       nodatabase => 1,
       cfg => $cfg,
       cgi => $cgi,
       fastcgi => $FCGI::global_request->IsFastCGI,
      );

  my $result = BSE::UI::FileProgress->dispatch($req);

  $req->output_result($result);
}

