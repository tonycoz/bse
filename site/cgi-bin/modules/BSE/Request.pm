package BSE::Request;
use strict;
use BSE::Session;
use CGI;
use BSE::Cfg;

sub new {
  my ($class) = @_;

  my $self =
    bless {
	   cfg => BSE::Cfg->new,
	   cgi => CGI->new,
	  }, $class;
  my %session;
  BSE::Session->tie_it(\%session, $self->{cfg});
  $self->{session} = \%session;

  $self;
}

sub cgi {
  return $_[0]{cgi};
}

sub cfg {
  return $_[0]{cfg};
}

sub session {
  return $_[0]{session};
}

sub extra_headers { return }

sub DESTROY {
  my ($self) = @_;
  if ($self->{session}) {
    undef $self->{session};
  }
}

1;
