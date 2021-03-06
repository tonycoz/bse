package BSE::EmailBlacklist;
use strict;
use Squirrel::Table;
use vars qw(@ISA $VERSION);
@ISA = qw(Squirrel::Table);
use BSE::EmailBlackEntry;

our $VERSION = "1.000";

sub rowClass {
  return 'BSE::EmailBlackEntry';
}

sub getEntry {
  my ($self, $email) = @_;

  return $self->getBy(email=>$email);
}

1;
