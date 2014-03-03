#!/usr/bin/perl -w
# -d:ptkdb
BEGIN { $ENV{DISPLAY} = '192.168.32.50:0.0' }
use strict;
use FindBin;
use lib "$FindBin::Bin/../modules";
use Carp 'confess';
use BSE::UI;

BSE::UI->run("BSE::UI::AdminNewsletter", silent_exit => 1);
