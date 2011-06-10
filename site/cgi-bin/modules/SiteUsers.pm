package SiteUsers;
use strict;
use Squirrel::Table;
use vars qw(@ISA $VERSION);
@ISA = qw(Squirrel::Table);
use SiteUser;

our $VERSION = "1.001";

sub rowClass {
  return 'SiteUser';
}

sub all_subscribers {
  my ($class) = @_;

  $class->getSpecial('allSubscribers');
}

sub all_ids {
  my ($class) = @_;

  map $_->{id}, BSE::DB->query('siteuserAllIds');
}

sub make {
  my ($self, %opts) = @_;

  require BSE::Passwords;
  my $password = delete $opts{password};
  my ($hash, $type) = BSE::Passwords->new_password_hash($password);

  $opts{password} = $hash;
  $opts{password_type} = $type;

  return $self->SUPER::make(%opts);
}

1;
