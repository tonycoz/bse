package BSE::TB::IPLockouts;
use strict;
use base 'Squirrel::Table';
use BSE::TB::IPLockout;
use BSE::Util::SQL;

our $VERSION = "1.000";

sub rowClass { "BSE::TB::IPLockout" }

sub active {
  my ($self, $ip_address, $type) = @_;

  my ($entry) = $self->getColumnBy
    (
     "id",
     [
      [ ip_address => $ip_address ],
      [ type => $type ],
      [ '>', expires => BSE::Util::SQL::now_datetime() ],
     ],
    );

  return defined $entry;
}

1;
