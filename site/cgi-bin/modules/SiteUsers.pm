package SiteUsers;
use strict;
use Squirrel::Table;
use vars qw(@ISA $VERSION);
@ISA = qw(Squirrel::Table);
use SiteUser;

our $VERSION = "1.000";

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

1;
