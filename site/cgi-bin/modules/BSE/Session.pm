package BSE::Session;
use strict;
use Constants qw(:session);
use CGI::Cookie;
use BSE::DB;

require $SESSION_REQUIRE;

my $saved;

sub tie_it {
  my ($self, $session, $cfg) = @_;
  
  my $lifetime = $cfg->entry('basic', 'cookie_lifetime') || '+3h';
  my %cookies = fetch CGI::Cookie;
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
    print "Set-Cookie: ",
    CGI::Cookie->new(-name=>'sessionid', -value=>$session->{_session_id}, 
		     -expires=>$lifetime, -path=>"/"),"\n";
  }
  $saved = $session;
}

sub change_cookie {
  my ($self, $session, $cfg, $sessionid, $newsession) = @_;

  my $lifetime = $cfg->entry('basic', 'cookie_lifetime') || '+3h';
  print "Set-Cookie: ",
  CGI::Cookie->new(-name=>'sessionid', -value=>$sessionid, 
		   -expires=>$lifetime, -path=>"/"),"\n";
  my $dh = BSE::DB->single;
  eval {
    tie %$newsession, $SESSION_CLASS, $sessionid,
    {
     Handle=>$dh->{dbh},
     LockHandle=>$dh->{dbh}
    };
  };
}

# this shouldn't be necessary, but it stopped working elsewhere and this
# fixed it
END {
  untie %$saved;
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

userid - 

=back

=head1 AUTHOR

Tony Cook <tony@develop-help.com>

=cut
