#!/usr/bin/perl -w
# -d:ptkdb
BEGIN { $ENV{DISPLAY} = '192.168.32.15:0.0' }
use strict;
use FindBin;
use CGI::Fast;
use lib "$FindBin::Bin/modules";
use BSE::DB;
use BSE::Request;
use BSE::Template;
use Carp 'confess';
use BSE::UI::NUser;

my $cfg = BSE::Cfg->new; # only do this once

$SIG{__DIE__} = sub { confess $@ };

while(my $cgi = CGI::Fast->new) {
  my $req = BSE::Request->new(cfg=>$cfg, cgi=>$cgi);

  my $result = BSE::UI::NUser->dispatch($req);

  BSE::Template->output_result($req, $result);
}

