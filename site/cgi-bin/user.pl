#!/usr/bin/perl -w
# -d:ptkdb
#BEGIN { $ENV{DISPLAY} = '192.168.32.97:0.0'; }
use strict;
use FindBin;
use lib "$FindBin::Bin/modules";
use Constants;
use BSE::Cfg;
use BSE::Session;
use BSE::UserReg;
use CGI;

my $cfg = BSE::Cfg->new;

my %session;
BSE::Session->tie_it(\%session, $cfg);

print STDERR "it's tied\n" if tied %session;
use Data::Dumper;
print STDERR Dumper \%session;

my %actions =
  (
   show_logon => 'show_logon',
   show_register => 'show_register',
   register => 'register',
   show_opts => 'show_opts',
   saveopts=>'saveopts',
   logon => 'logon',
   logoff => 'logoff',
   userpage=>'userpage',
   download=>'download',
   show_lost_password => 'show_lost_password',
   lost_password => 'lost_password',
  );

my $cgi = CGI->new;

my ($action) = grep $cgi->param($_) || $cgi->param("$_.x"), keys %actions;
$action ||= 'show_logon';
my $method = $actions{$action};

BSE::UserReg->$method(\%session, $cgi, $cfg);

untie %session;
