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
    my $cookie = CGI::Cookie->new(-name=>'sessionid', -value=>$session->{_session_id}, 
		     -expires=>$lifetime, -path=>"/");
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
    print "Set-Cookie: ", $cookie,"\n";
    print STDERR "Sent cookie: $cookie\n" if $debug;
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
