#!/usr/bin/perl -w
# -d:ptkdb
BEGIN { $ENV{DISPLAY} = '192.168.32.54:0.0' }
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
$req->output_result($result);
