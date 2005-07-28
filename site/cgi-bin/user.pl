#!/usr/bin/perl -w
# -d:ptkdb
BEGIN { $ENV{DISPLAY} = '192.168.32.15:0.0'; }
use strict;
use FindBin;
use lib "$FindBin::Bin/modules";
use Constants;
use BSE::Session;
use BSE::UserReg;
use BSE::Request;

my $req = BSE::Request->new;

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
   download_file=>'download_file',
   show_lost_password => 'show_lost_password',
   lost_password => 'lost_password',
   subinfo => 'subinfo',
   blacklist => 'blacklist',
   confirm => 'confirm',
   unsub => 'unsub',
   setcookie => 'set_cookie',
   nopassword => 'nopassword',
   a_image => 'req_image',
   a_orderdetail => 'req_orderdetail',
  );

my $cgi = $req->cgi;

my ($action) = grep $cgi->param($_) || $cgi->param("$_.x"), keys %actions;
$action ||= 'userpage';
my $method = $actions{$action};

BSE::UserReg->$method($req);

