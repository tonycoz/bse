package BSE::SessionSign;
use strict;
use BSE::Cfg;

our $VERSION = "1.000";

sub _sign {
  my ($self, $sessionid, $when) = @_;

  require Digest::SHA;

  my $secret = BSE::Cfg->single->entryErr("site", "secret");
  my $sha = Digest::SHA::sha256_base64($secret, $sessionid, $when);

  return $when . "." . $sha;
}

sub make {
  my ($self, $sessionid) = @_;

  my $now = time;

  return $self->_sign($sessionid, $now);
}

sub check {
  my ($self, $sessionid, $sig, $error) = @_;

  my $now = time;
  my ($then, $sha) = split /\./, $sig, 2;

  my $good_sig = $self->_sign($sessionid, $then);

  if ($good_sig ne $sig) {
    require BSE::TB::AuditLog;
    BSE::TB::AuditLog->log
	(
	 component => "user::setcookie",
	 level => "warning",
	 actor => "S",
	 msg => "Bad signature setting session cookie",
	 dump => <<DUMP,
Received:
sessionid: $sessionid
sig: $sig
DUMP
	);
    $$error = "BADSIG";
    return;
  }

  require BSE::TB::AuditLog;
  unless ($then + 30 > $now) {
    require BSE::TB::AuditLog;
    BSE::TB::AuditLog->log
	(
	 component => "user::setcookie",
	 level => "warning",
	 actor => "S",
	 msg => "Too old setting session cookie",
	 dump => <<DUMP,
Received:
then: $then
now: $now
DUMP
	);
    $$error = "OLDSIG";
    return 0;
  }

  return 1;
}

1;
