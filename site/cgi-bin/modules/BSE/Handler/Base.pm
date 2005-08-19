package BSE::Handler::Base;
use strict;
use BSE::Cfg;
use Apache::Request;
use BSE::Request;

sub handler {
  my ($class, $r) = @_;

  my $cgi = Apache::Request->new($r);

  my $cfg_path = $r->dir_config('BSEConfig');
  my $cfg = BSE::Cfg->new(path => $cfg_path);
  my $req = BSE::Request->new(cgi=>$cgi, cfg=>$cfg);

  my $result = $class->dispatch($req);

  BSE::Template->output_result($req, $result);
}

1;
