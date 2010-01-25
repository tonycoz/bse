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
           ccStatus2 ccTranId complete delivOrganization billOrganization
           delivStreet2 billStreet2 purchase_order shipping_method
           shipping_name shipping_trace/;
}

sub defaults {
  require BSE::Util::SQL;
  require Digest::MD5;
  return
    (
     total => 0,
     wholesaleTotal => 0,
     gst => 0,
     orderDate => BSE::Util::SQL::now_datetime(),
     filled => 0,
     whenFilled => undef,
     whoFilled => '',
     paidFor => 0,
     paymentReceipt => '',
     randomId => Digest::MD5::md5_hex(time().rand().{}.$$),
     ccNumberHash => '',
     ccName => '',
     ccExpiryHash => '',
     ccType => '',
     randomId => '',
     cancelled => 0,
     userId => '',
     paymentType => 0,
     customInt1 => undef,
     customInt2 => undef,
     customInt3 => undef,
     customInt4 => undef,
     customInt5 => undef,
     customStr1 => undef,
     customStr2 => undef,
     customStr3 => undef,
     customStr4 => undef,
     customStr5 => undef,
     instructions => '',
     siteuser_id => undef,
     affiliate_code => '',
     shipping_cost => 0,
     ccOnline => 0,
     ccSuccess => 0,
     ccReceipt => '',
     ccStatus => 0,
     ccStatusText => '',
     ccStatus2 => '',
     ccTranId => '',
     complete => 0,
     purchase_order => '',
     shipping_method => '',
     shipping_name => '',
     shipping_trace => undef,
    );
}

sub address_columns {
  return qw/
           delivFirstName delivLastName delivStreet delivSuburb delivState
	   delivPostCode delivCountry
           billFirstName billLastName billStreet billSuburb billState
           billPostCode billCountry
           telephone facsimile emailAddress
           instructions billTelephone billFacsimile billEmail
           delivMobile billMobile
           delivOrganization billOrganization
           delivStreet2 billStreet2/;
}

sub user_columns {
  return qw/userId siteuser_id/;
}

sub payment_columns {
  return qw/ccNumberHash ccName ccExpiryHash ccType
           paidFor paymentReceipt paymentType
           ccOnline ccSuccess ccReceipt ccStatus ccStatusText
           ccStatus2 ccTranId/;
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
     delivFirstName => { description=>'Delivery First Name', 
			 rules=>'dh_one_line' },
     delivLastName => { description => 'Delivery Last Name', 
			 rules=>'dh_one_line'  },
     delivOrganization => { description => 'Delivery Organization', 
			    rules=>'dh_one_line'  },
     delivStreet => { description => 'Delivery Street', 
			 rules=>'dh_one_line'  },
     delivStreet2 => { description => 'Delivery Street 2', 
			 rules=>'dh_one_line'  },
     delivState => { description => 'Delivery State', 
			 rules=>'dh_one_line'  },
     delivSuburb => { description => 'Delivery Suburb', 
			 rules=>'dh_one_line'  },
     delivPostCode => { description => 'Delivery Post Code', 
			 rules=>'dh_one_line;dh_int_postcode'  },
     delivCountry => { description => 'Delivery Country', 
			 rules=>'dh_one_line'  },
     billFirstName => { description => 'Billing First Name', 
			 rules=>'dh_one_line'  },
     billLastName => { description => 'Billing Last Name', 
			 rules=>'dh_one_line'  },
     billOrganization => { description => 'Billing Organization', 
			   rules=>'dh_one_line'  },
     billStreet => { description => 'Billing Street', 
			 rules=>'dh_one_line'  },
     billStreet2 => { description => 'Billing Street 2', 
			 rules=>'dh_one_line'  },
     billSuburb => { description => 'Billing Suburb', 
			 rules=>'dh_one_line'  },
     billState => { description => 'Billing State', 
			 rules=>'dh_one_line'  },
     billPostCode => { description => 'Billing Post Code', 
			 rules=>'dh_one_line;dh_int_postcode'  },
     billCountry => { description => 'Billing First Name', 
			 rules=>'dh_one_line'  },
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
     purchase_order => { description => 'Purchase Order No' },
     shipping_cost => { description => 'Shipping charges' },
     shipping_method => { description => 'Shipping method' },
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

sub add_item {
  my ($self, %opts) = @_;

  my $prod = delete $opts{product}
    or confess "Missing product option";
  my $units = delete $opts{units} || 1;

  my $options = '';
  my @dboptions;
  if ($opts{options}) {
    if (ref $opts{options}) {
      @dboptions = @{delete $opts{options}};
    }
    else {
      $options = delete $opts{options};
    }
  }
  
  require BSE::TB::OrderItems;
  my %item =
    (
     productId => $prod->id,
     orderId => $self->id,
     units => $units,
     price => $prod->retailPrice,
     options => $options,
     max_lapsed => 0,
     session_id => 0,
     ( map { $_ => $prod->{$_} }
       qw/wholesalePrice gst customInt1 customInt2 customInt3 customStr1 customStr2 customStr3 title description subscription_id subscription_period product_code/
     ),
    );

  $self->set_total($self->total + $prod->retailPrice * $units);

  return BSE::TB::OrderItems->make(%item);
}

1;
