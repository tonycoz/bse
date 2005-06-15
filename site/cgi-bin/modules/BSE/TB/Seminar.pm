package BSE::TB::Seminar;
use strict;
# represents a seminar from the database
use Product;
use vars qw/@ISA/;
@ISA = qw/Product/;

# subscription_usage values
use constant SUBUSAGE_START_ONLY => 1;
use constant SUBUSAGE_RENEW_ONLY => 2;
use constant SUBUSAGE_EITHER => 3;

sub columns {
  return ($_[0]->SUPER::columns(), 
	  qw/seminar_id duration/ );
}

sub bases {
  return { seminar_id=>{ class=>'Product'} };
}

1;
