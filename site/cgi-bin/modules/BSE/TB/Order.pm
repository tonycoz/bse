package BSE::TB::Order;
use strict;
# represents an order from the database
use Squirrel::Row;
use vars qw/@ISA/;
@ISA = qw/Squirrel::Row/;
use Carp 'confess';

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
           instructions billTelephone billFacsimile billEmail
           siteuser_id affiliate_code shipping_cost
           delivMobile billMobile
           ccOnline ccSuccess ccReceipt ccStatus ccStatusText
           ccStatus2 ccTranId complete/;
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

sub items {
  my ($self) = @_;

  require BSE::TB::OrderItems;
  return BSE::TB::OrderItems->getBy(orderId => $self->{id});
}

sub files {
  my ($self) = @_;

  BSE::DB->query(orderFiles=>$self->{id});
}

sub products {
  my ($self) = @_;

  require Products;
  Products->getSpecial(orderProducts=>$self->{id});
}

sub valid_fields {
  my ($class, $cfg) = @_;

  my %fields =
    (
     delivFirstName => { description=>'Delivery First Name', },
     delivLastName => { description => 'Delivery Last Name' },
     delivStreet => { description => 'Delivery Street' },
     delivState => { description => 'Delivery State' },
     delivSuburb => { description => 'Delivery Suburb' },
     delivPostCode => { description => 'Delivery Post Code' },
     delivCountry => { description => 'Delivery Country' },
     billFirstName => { description => 'Billing First Name' },
     billLastName => { description => 'Billing Last Name' },
     billStreet => { description => 'Billing First Name' },
     billSuburb => { description => 'Billing First Name' },
     billState => { description => 'Billing First Name' },
     billPostCode => { description => 'Billing First Name' },
     billCountry => { description => 'Billing First Name' },
     telephone => { description => 'Telephone Number',
		    rules => "phone" },
     facsimile => { description => 'Facsimile Number',
		    rules => 'phone' },
     emailAddress => { description => 'Email Address',
		       rules=>'email;required' },
     instructions => { description => 'Instructions' },
     billTelephone => { description => 'Billing Telephone Number', 
			rules=>'phone' },
     billFacsimile => { description => 'Billing Facsimile Number',
			rules=>'phone' },
     billEmail => { description => 'Billing Email Address',
		    rules => 'email' },
     delivMobile => { description => 'Delivery Mobile Number',
		      rules => 'phone' },
     billMobile => { description => 'Billing Mobile Number',
		     rules=>'phone' },
     instructions => { description => 'Instructions' },
    );

  for my $field (keys %fields) {
    my $display = $cfg->entry('shop', "display_$field");
    $display and $fields{$field}{description} = $display;
  }

  return %fields;
}

sub valid_rules {
  my ($class, $cfg) = @_;

  return;
}

sub valid_payment_fields {
  my ($class, $cfg) = @_;

  my %fields =
    (
     cardNumber => 
     { 
      description => "Credit Card Number",
      rules=>"creditcardnumber",
     },
     cardExpiry => 
     {
      description => "Credit Card Expiry Date",
      rules => 'creditcardexpirysingle',
     },
     cardHolder => { description => "Credit Card Holder" },
     cardType => { description => "Credit Card Type" },
     cardVerify => 
     { 
      description => 'Card Verification Value',
      rules => 'creditcardcvv',
     },
    );

  for my $field (keys %fields) {
    my $display = $cfg->entry('shop', "display_$field");
    $display and $fields{$field}{description} = $display;
  }

  return %fields;
}

sub valid_payment_rules {
  return;
}

sub clear_items {
  my ($self) = @_;

  confess "Attempt to clear items on completed order $self->{id}"
    if $self->{complete};
  
  BSE::DB->run(deleteOrdersItems => $self->{id});
}

1;
