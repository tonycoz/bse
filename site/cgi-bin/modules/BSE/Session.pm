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
		     -expires=>$lifetime),"\n";
  }
  $saved = $session;
}

# this shouldn't be necessary, but it stopped working elsewhere and this
# fixed it
END {
  untie %$saved;
}

1;
