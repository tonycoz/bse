package SiteUser;
use strict;
# represents a registered user
use Squirrel::Row;
use vars qw/@ISA/;
@ISA = qw/Squirrel::Row/;

sub columns {
  return qw/id userId password email keepAddress whenRegistered lastLogon
            name1 name2 address city state postcode telephone facsimile 
            country wantLetter/;
}

1;
