#!/usr/bin/perl -w
# -d:ptkdb
BEGIN { $ENV{DISPLAY} = '192.168.32.54:0.0' }
use strict;
use FindBin;
#use CGI::Carp 'fatalsToBrowser';
use Carp 'verbose'; # remove the 'verbose' in production
use Carp 'confess';
use lib "$FindBin::Bin/../modules";
use BSE::UI;

BSE::UI->run("BSE::UI::AdminPage");

