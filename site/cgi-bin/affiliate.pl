#!/usr/bin/perl -w
# -d:ptkdb
BEGIN { $ENV{DISPLAY} = '192.168.32.15:0.0' }
use strict;
use FindBin;
use lib "$FindBin::Bin/modules";
use BSE::DB;
use BSE::Request;
use BSE::Template;
use Carp 'confess';
use BSE::UI::Affiliate;

$SIG{__DIE__} = sub { confess $@ };

my $req = BSE::Request->new;
my $result = BSE::UI::Affiliate->dispatch($req);
BSE::Template->output_result($req, $result);

__END__
=head1 NAME

affiliate.pl - set the affiliate code for new orders or display a user info page

=head1 SYNOPSIS

# display a user's information or affiliate page
http://your.site.com/cgi-bin/affiliate.pl?id=I<number>

# set the stored affiliate code and refresh to the top of the site
http://your.site.com/cgi-bin/affiliate.pl?a_set=1&id=I<code>

=head1 DESCRIPTION

This is implemented by L<BSE::UI::Affiliate>, please see that for
complete documentation.

=head1 AUTHOR

Tony Cook <tony@develop-help.com>

=cut
