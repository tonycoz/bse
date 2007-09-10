#!/usr/bin/perl -w
use strict;
use FindBin;
use lib "$FindBin::Bin/modules";
use CGI::Fast;
use BSE::Request;
use BSE::UI::Thumb;
use BSE::Template;
use Carp 'confess';

my $cfg = BSE::Cfg->new; # only do this once

$SIG{__DIE__} = sub { confess $@ };

while(my $cgi = CGI::Fast->new) {
  my $req = BSE::Request->new(cfg=>$cfg, cgi=>$cgi);

  my $result = BSE::UI::Thumb->dispatch($req);
  BSE::Template->output_result($req, $result);
}

