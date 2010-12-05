package BSE::TB::Location;
use strict;
use base qw(Squirrel::Row);

our $VERSION = "1.001";

sub columns {
  return qw/id 
            description 
            room street1 street2 suburb state country postcode 
            public_notes 
            bookings_name bookings_phone bookings_fax bookings_url 
            facilities_name facilities_phone 
            admin_notes disabled/;
}

sub valid_fields {
  return
    (
     description => { description => "Description",
		      rules => 'required', maxlength=>255, width=>60 },
     room => { description => 'Room', maxlength=>40, width=>20 },
     street1 => { description => 'Street Address 1', required => 1,
		  maxlength=>255, width=>50 },
     street2 => { description => 'Street Address 2',
		  maxlength=>255, width=>50 },
     suburb => { description => 'Suburb', required => 1,
		 maxlength=>255, width=>50 },
     state => { description => 'State', required => 1,
		maxlength=>80, width=>15 },
     country => { description => 'Country', maxlength=>80, width => 30 },
     postcode => { description => 'Post Code', 
		   rules => 'postcode', 
		   required => 1, maxlength=>40, width=>5 },
     public_notes => { description => 'Notes', width=>60, height=>10 },
     bookings_name => { description => 'Bookings Contact Name',
			maxlength=>80, width=>50 },
     bookings_phone => { description => 'Bookings Contact Phone',
			 rules => 'phone',
		       maxlength=>80, width=>30 },
     bookings_fax => { description => 'Bookings Contact Fax',
		       rules => 'phone',
		       maxlength=>80, width=>30 },
     bookings_url => { description => 'Bookings URL',
		       rules => 'weburl',
		     maxlength=>255, width=>60 },
     facilities_name => { description => 'Facilities Contact Name',
			  maxlength=>255, width=>60 },
     facilities_phone => { description => 'Facilities Contact Phone',
			   rules => 'phone',
			 maxlength=>80, width=>30 },
     admin_notes => { description => 'Administration Notes',
		      width=>60, height=>10},
    );
}

sub valid_rules {
  # no rules yet
  return;
}

sub is_removable {
  my ($self) = @_;

  return 1; # this will change
}

sub sessions_detail {
  my ($self) = @_;

  BSE::DB->query(bse_locationSessionDetail => $self->{id});
}

1;
