package BSE::TB::Subscription;
use strict;
use Squirrel::Row;
use vars qw/@ISA/;
@ISA = qw/Squirrel::Row/;

sub columns {
  return qw/subscription_id text_id title description max_lapsed/;
}

sub primary { 'subscription_id' }

# call as a method for edits
sub valid_rules {
  my ($self, $cfg) = @_;

  my @subs = BSE::TB::Subscriptions->all;
  if (ref $self) {
    @subs = grep $_->{subscription_id} != $self->{subscription_id}, @subs;
  }
  my $notsubid_match = join '|', map $_->{text_id}, @subs;

  return
    (
     identifier => { match => qr/^\w+$/,
		   error => '$n must contain only letters and digits, and no spaces' },
     notsubid => { nomatch => qr/^(?:$notsubid_match)$/,
		 error => 'Duplicate identifier' },
    );
}

sub valid_fields {
  return
    (
     text_id => { description=>"Identifier", 
		  rules=>'required;identifier;notsubid' },
     title => { description=>"Title",
		required => 1 },
     description => { description=>"Description" },
     max_lapsed => { description => 'Max lapsed', 
		     rules => 'required;natural', },
    );
}

1;
