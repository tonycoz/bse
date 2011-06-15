package BSE::TB::TagMember;
use strict;
use base 'Squirrel::Row';

our $VERSION = "1.000";

sub columns { qw(id owner_type owner_id tag_id) }

sub table { 'bse_tag_members' }

1;

