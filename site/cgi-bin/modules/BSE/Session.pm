package BSE::Session;
use strict;
use Constants qw(:session);
use CGI::Cookie;
use BSE::DB;

require $SESSION_REQUIRE;

sub tie_it {
  my ($self, $session, $cfg) = @_;
  
  my $lifetime = $cfg->entry('basic', 'cookie_lifetime') || '+3h';
  my $debug = $cfg->entry('debug', 'cookies');
  my %cookies = fetch CGI::Cookie;
  if ($debug) {
    require Data::Dumper;
    print STDERR "Received cookies: ", Data::Dumper::Dumper(\%cookies);
  }
  my $sessionid;
  $sessionid = $cookies{sessionid}->value if exists $cookies{sessionid};

  my $dh = BSE::DB->single;
  eval {
    tie %$session, $SESSION_CLASS, $sessionid,
    {
     Handle=>$dh->{dbh},
     LockHandle=>$dh->{dbh}
    };
  };
  print STDERR "Error getting session: $@\n" if $@ && $debug;
  if ($@ && $@ =~ /Object does not exist/) {
    # try again
    undef $sessionid;
    tie %$session, $SESSION_CLASS, $sessionid,
    {
     Handle=>$dh->{dbh},
     LockHandle=>$dh->{dbh}
    };
  }
  unless ($sessionid) {
  # save the new sessionid
    my $cookie = $self->make_cookie($cfg, sessionid => $session->{_session_id});
# from trying to debug Opera cookie issues
#     my ($value, @rest) = split ';', $cookie;
#     my @out = $value;
#     my %rest;
#     for my $entry (@rest) {
#       my ($key) = $entry =~ /^\s*(\w+)=/
# 	or next;
#       $rest{$key} = $entry;
#     }
#     for my $field (qw/expires path domain/) {
#       push @out, $rest{$field}
# 	if $rest{$field};
#     }
#     $cookie = join ';', @out;
    BSE::Session->send_cookie($cookie);
    print STDERR "Sent cookie: $cookie\n" if $debug;
  }

  if ($cfg->entry('debug', 'dump_session')) {
    require Data::Dumper;
    print STDERR Data::Dumper->Dump([ $session ], [ 'session' ]);
  }
}

sub change_cookie {
  my ($self, $session, $cfg, $sessionid, $newsession) = @_;

  BSE::Session->send_cookie($self->make_cookie($cfg, 'sessionid', $sessionid));
  my $dh = BSE::DB->single;
  eval {
    tie %$newsession, $SESSION_CLASS, $sessionid,
    {
     Handle=>$dh->{dbh},
     LockHandle=>$dh->{dbh}
    };
  };
}

sub make_cookie {
  my ($self, $cfg, $name, $value, $lifetime) = @_;

  $lifetime ||= $cfg->entry('basic', 'cookie_lifetime') || '+3h';
  my %opts =
    (
     -name => $name,
     -value => $value,
     -path=> '/',
     -expires=>$lifetime,
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

1;

=head1 NAME

BSE::Session - wrapper around Apache::Session for BSE.

=head1 SYNOPSIS

  use BSE::Session;
  use BSE::Cfg
  my %session;
  my $cfg = BSE::Cfg->new;
  BSE::Session->tie_it(\%session, $cfg);

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
