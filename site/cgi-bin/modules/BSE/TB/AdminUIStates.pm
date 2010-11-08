package BSE::TB::AdminUIStates;
use strict;
use base "Squirrel::Table";
use BSE::TB::AdminUIState;

our $VERSION = "1.000";

sub rowClass {
  "BSE::TB::AdminUIState";
}

sub user_matching_state {
  my ($self, $user, $prefix) = @_;

  return $self->getSpecial(matchingState => $user->id, $prefix . "%");
}

sub user_state {
  my ($self, $user, $name) = @_;

  return $self->getBy(user_id => $user->id, name => $name);
}

1;
