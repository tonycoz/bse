package SiteUser;
use strict;
# represents a registered user
use Squirrel::Row;
use vars qw/@ISA/;
@ISA = qw/Squirrel::Row/;

sub columns {
  return qw/id userId password email keepAddress whenRegistered lastLogon
            name1 name2 address city state postcode telephone facsimile 
            country wantLetter confirmed confirmSecret waitingForConfirmation
            textOnlyMail title organization referral otherReferral
            prompt otherPrompt profession otherProfession/;
}

sub removeSubscriptions {
  my ($self) = @_;

  SiteUsers->doSpecial('removeSubscriptions', $self->{id});
}

1;
