package BSE::Session;
use strict;
use CGI::Cookie;
use BSE::DB;
use BSE::CfgInfo qw/custom_class/;

our $VERSION = "1.001";

sub _session_require {
  my ($cfg) = @_;

  my $class = _session_class($cfg);
  $class =~ s!::!/!g;

  return "$class.pm";
}

sub _session_class {
  my ($cfg) = @_;

  eval { require Constants; };

  my $default = $Constants::SESSION_CLASS || 'Apache::Session::MySQL';

  return $cfg->entry('basic', 'session_class', $default);
}

sub _send_session_cookie {
  my ($self, $session, $cfg) = @_;

  my $debug = $cfg->entry('debug', 'cookies');

  my $cookie_name = $cfg->entry('basic', 'cookie_name', 'sessionid');
  my %extras;
  if ($cfg->entry("basic", "http_only_session", 1)) {
    $extras{httponly} = 1;
  }
  if ($cfg->entry("basic", "secure_session")) {
    $extras{secure} = 1;
  }
  my $cookie = $self->make_cookie($cfg, $cookie_name => $session->{_session_id}, \%extras);
  BSE::Session->send_cookie($cookie);

  print STDERR "Sent cookie: $cookie\n" if $debug;

  my $custom = custom_class($cfg);
  if ($custom->can('send_session_cookie')) {
    $custom->send_session_cookie($cookie_name, $session, $session->{_session_id}, $cfg);
  }
}

sub tie_it {
  my ($self, $session, $cfg) = @_;

  my $require = _session_require($cfg);
  require $require;

  my $cookie_name = $cfg->entry('basic', 'cookie_name', 'sessionid');
  my $lifetime = $cfg->entry('basic', 'cookie_lifetime') || '+3h';
  my $debug = $cfg->entry('debug', 'cookies');
  my %cookies = fetch CGI::Cookie;
  if ($debug) {
    require Data::Dumper;
    print STDERR "Received cookies: ", Data::Dumper::Dumper(\%cookies);
  }
  my $sessionid;
  $sessionid = $cookies{$cookie_name}->value if exists $cookies{$cookie_name};

  my $dh = BSE::DB->single;
  eval {
    tie %$session, _session_class($cfg), $sessionid,
    {
     Handle=>$dh->{dbh},
     LockHandle=>$dh->{dbh}
    };
  };
  print STDERR "Error getting session: $@\n" if $@ && $debug;
  if ($@ && $@ =~ /Object does not exist/) {
    # try again
    undef $sessionid;
    tie %$session, _session_class($cfg), $sessionid,
    {
     Handle=>$dh->{dbh},
     LockHandle=>$dh->{dbh}
    };
  }
  unless ($sessionid) {
    # save the new sessionid
    $self->_send_session_cookie($session, $cfg);
  }

  if ($cfg->entry('debug', 'dump_session')) {
    require Data::Dumper;
    print STDERR Data::Dumper->Dump([ $session ], [ 'session' ]);
  }
}

sub change_cookie {
  my ($self, $session, $cfg, $sessionid, $newsession) = @_;

  #my $cookie_name = $cfg->entry('basic', 'cookie_name', 'sessionid');
  #BSE::Session->send_cookie($self->make_cookie($cfg, $cookie_name, $sessionid));
  my $dh = BSE::DB->single;
  eval {
    tie %$newsession, _session_class($cfg), $sessionid,
    {
     Handle=>$dh->{dbh},
     LockHandle=>$dh->{dbh}
    };
  };

  $self->_send_session_cookie($newsession, $cfg);
}

sub make_cookie {
  my ($self, $cfg, $name, $value, $extras) = @_;

  $extras ||= {};
  $extras->{lifetime} ||= $cfg->entry('basic', 'cookie_lifetime') || '+3h';
  $name = $cfg->entry('cookie names', $name, $name);
  my %opts =
    (
     -name => $name,
     -value => $value,
     -path => '/',
     map {; "-$_" => $extras->{$_} } keys %$extras,
    );
  my $domain = $ENV{HTTP_HOST};
  $domain =~ s/:\d+$//;
  $domain = $cfg->entry('basic', 'cookie_domain', $domain);
  if ($domain !~ /^\d+\.\d+\.\d+\.\d+$/) {
    $opts{"-domain"} = $domain;
  }

  return CGI::Cookie->new(%opts);
}

sub send_cookie {
  my ($class, $cookie) = @_;

  if (exists $ENV{GATEWAY_INTERFACE}
      && $ENV{GATEWAY_INTERFACE} =~ /^CGI-Perl\//) {
    my $r = Apache->request or die;
    $r->header_out('Set-Cookie' => "$cookie");
  }
  else {
    print "Set-Cookie: $cookie\n";
  }
}

sub clear {
  my ($class, $session) = @_;

  my $tie = tied(%$session);
  if ($tie) {
    $tie->delete();
  }
}

1;

=head1 NAME

BSE::Session - wrapper around Apache::Session for BSE.

=head1 SYNOPSIS

  use BSE::Session;
  use BSE::Cfg
  my %session;
  my $cfg = BSE::Cfg->new;
  BSE::Session->tie_it(\%session, $cfg);

  BSE::Session->clear($session);

=head1 DESCRIPTION

Provides a thinnish wrapper around Apache::Session, providing the interface
to BSE's database abstraction, configuration, retries and cookie setup.

=head1 KEYS

=over

=item *

cart - the customer's shopping cart, should only be set on the secure side

=item *

custom - custom values set by shopping cart processing, should only be
set on the secure side

=item *

userid - id of the logged on normal user.

=item *

adminuserid - id of the logged on admin user.

=item *

affiliate_code - id of the affiliate set by affiliate.pl

=back

=head1 AUTHOR

Tony Cook <tony@develop-help.com>

=cut
