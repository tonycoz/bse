package BSE::EmailRequests;
use strict;
use Squirrel::Table;
use vars qw(@ISA $VERSION);
@ISA = qw(Squirrel::Table);
use BSE::EmailRequest;

our $VERSION = "1.000";

sub rowClass {
  return 'BSE::EmailRequest';
}

sub getEntry {
  my ($self, $email) = @_;

  return $self->getBy(email=>$email);
}

1;
