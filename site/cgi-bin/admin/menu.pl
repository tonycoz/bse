#!/usr/bin/perl -w
# -d:ptkdb
BEGIN { $ENV{DISPLAY} = '192.168.32.15:0.0' }
use strict;
use FindBin;
use lib "$FindBin::Bin/../modules";
use BSE::DB;
use BSE::Request;
use BSE::Template;
use Carp 'confess';
use BSE::AdminMenu;

$SIG{__DIE__} = sub { confess $@ };

my $req = BSE::Request->new;

my $result = BSE::AdminMenu->dispatch($req);
$| = 1;
push @{$result->{headers}}, "Content-Type: $result->{type}";
push @{$result->{headers}}, $req->extra_headers;
if (exists $ENV{GATEWAY_INTERFACE}
    && $ENV{GATEWAY_INTERFACE} =~ /^CGI-Perl\//) {
  use Apache;
  my $r = Apache->request or die;
  $r->send_cgi_header(join("\n", @{$result->{headers}})."\n");
}
else {
  print "$_\n" for @{$result->{headers}};
  print "\n";
}
print $result->{content};
