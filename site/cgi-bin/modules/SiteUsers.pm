package SiteUsers;
use strict;
use Squirrel::Table;
use vars qw(@ISA $VERSION);
@ISA = qw(Squirrel::Table);
use SiteUser;

our $VERSION = "1.002";

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

sub _lost_user {
  my ($self, $id, $error) = @_;

  my ($user) = SiteUsers->getBy(lost_id => $id);
  unless ($user) {
    $$error = "unknownid";
    return;
  }

  require BSE::Util::SQL;
  my $lost_limit_days = BSE::Cfg->single->entry("lost password", "age_limit", 7);
  my $check_date = BSE::Util::SQL::sql_add_date_days($user->lost_date, $lost_limit_days);

  my $today = BSE::Util::SQL::now_sqldate();

  if ($check_date lt $today) {
    $$error = "expired";
    return;
  }

  return $user;
}

sub lost_password_next {
  my ($self, $id, $error) = @_;

  my $user = $self->_lost_user($id, $error)
    or return;

  return $user;
}

sub lost_password_save {
  my ($self, $id, $password, $error) = @_;

  my $user = $self->_lost_user($id, $error)
    or return;

  $user->changepw($password, $user,
		  component => "siteusers:lost:changepw",
		  msg => "Account recovered");
  $user->set_lost_id("");
  $user->save;

  return 1;
}

1;
