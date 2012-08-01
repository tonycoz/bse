#!/usr/bin/perl -w
use strict;
use FindBin;
use lib "$FindBin::Bin/../modules";
use BSE::UI;

BSE::UI->run("BSE::UI::AdminImageClean", silent_exit => 1 );
