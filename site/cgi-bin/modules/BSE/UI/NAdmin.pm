package BSE::UI::NAdmin;
use strict;
use base qw/BSE::UI::NUser/;

our $VERSION = "1.000";

sub controller_section {
  'nadmin controllers';
}

1;

__END__

=head1 NAME

BSE::UI::NAdmin - dispatcher for admin side functionality.

=cut
