#!/usr/bin/perl -w
# -d:ptkdb
BEGIN { $ENV{DISPLAY} = '192.168.32.51:0.0' }
use strict;
use FindBin;
use CGI::Fast;
use lib "$FindBin::Bin/modules";
use BSE::DB;
use BSE::Request;
use BSE::Template;
use Carp 'confess';
use BSE::UI::Page;

my $cfg = BSE::Cfg->new; # only do this once

$SIG{__DIE__} = sub { confess $@ };

while(my $cgi = CGI::Fast->new) {
  my $req = BSE::Request->new(cfg=>$cfg, cgi=>$cgi);

  my $result = BSE::UI::Page->new->dispatch($req);

  BSE::Template->output_result($req, $result);
}

