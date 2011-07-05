#!/usr/bin/perl -w
# -d:ptkdb
BEGIN { $ENV{DISPLAY} = '192.168.32.51:0.0' }
use strict;
use FindBin;
use lib "$FindBin::Bin/modules";
use BSE::UI;

BSE::UI->run_fcgi("BSE::UI::Page");
