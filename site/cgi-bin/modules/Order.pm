package Order;
use strict;
# represents an order from the database
use Squirrel::Row;
use vars qw/@ISA/;
@ISA = qw/Squirrel::Row/;

sub columns {
  return qw/id
           delivFirstName delivLastName delivStreet delivSuburb delivState
	   delivPostCode delivCountry
           billFirstName billLastName billStreet billSuburb billState
           billPostCode billCountry
           telephone facsimile emailAddress
           total wholesaleTotal gst orderDate
           ccNumberHash ccName ccExpiryHash ccType
           filled whenFilled whoFilled paidFor paymentReceipt
           randomId cancelled userId paymentType
           customInt1 customInt2 customInt3 customInt4 customInt5
           customStr1 customStr2 customStr3 customStr4 customStr5
           instructions billTelephone billFacsimile billEmail/;
}

=item siteuser

returns the SiteUser object of the user who made this order.

=cut

sub siteuser {
  my ($self) = @_;

  $self->{userId} or return;

  require SiteUsers;

  return ( SiteUsers->getBy(userId=>$self->{userId}) )[0];
}

1;
