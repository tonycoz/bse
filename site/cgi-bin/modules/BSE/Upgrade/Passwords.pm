package BSE::Upgrade::Passwords;
use strict;
use BSE::TB::SiteUsers;
use BSE::TB::AdminUsers;

our $VERSION = "1.001";

sub upgrade {
  my ($class, %opts) = @_;

  $class->_upgrade_siteusers(%opts);
  $class->_upgrade_adminusers(%opts);
}

sub _upgrade_siteusers {
  my ($class, %opts) = @_;

  my @users = BSE::TB::SiteUsers->getBy
    (
     password_type => "plain",
    );
  $opts{progress}->("Upgrading site user passwords")
    if $opts{actions};
  $opts{progress}->("Found ", scalar @users, " users to upgrade")
    if $opts{verbose};

  $opts{progress}->("  Not actually doing any password upgrades")
    if $opts{nothing};
  for my $user (@users) {
    $opts{progress}->("  Hashing password for site user '", $user->userId, "'");
    unless ($opts{nothing}) {
      $user->changepw
	(
	 $user->password,
	 'S',
	 msg => "Password for '" . $user->userId . "' hashed",
	);
      $user->save;
    }
  }
}

sub _upgrade_adminusers {
  my ($class, %opts) = @_;

  my @users = BSE::TB::AdminUsers->getBy
    (
     password_type => "plain",
    );
  $opts{progress}->("Upgrading admin user passwords")
    if $opts{actions};
  $opts{progress}->("Found ", scalar @users, " users to upgrade")
    if $opts{verbose};

  $opts{progress}->("  Not actually doing any password upgrades")
    if $opts{nothing};
  for my $user (@users) {
    $opts{progress}->("  Hashing password for admin user '", $user->logon, "'");
    unless ($opts{nothing}) {
      # NOTE: the logging parameters aren't used yet
      $user->changepw
	(
	 $user->password,
	 'S',
	 msg => "Password for admin user '" . $user->logon . "' hashed",
	);
      $user->save;
    }
  }
}

1;
