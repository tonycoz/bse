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

sub user {
  return $_[0]{adminuser};
}

sub setuser {
  $_[0]{adminuser} = $_[1];
}

sub url {
  my ($self, $action, $params, $name) = @_;

  my $url = $self->cfg->entryErr('site', 'url');
  $url .= "/cgi-bin/admin/$action.pl";
  if ($params && keys %$params) {
    $url .= "?" . join("&", map { "$_=".encode_entities($params->{$_}) } keys %$params);
  }
  $url .= "#$name" if $name;

  $url;
}

sub user_can {
  my ($self, $perm, $object, $rmsg) = @_;

  return 1 unless $self->{user};
  require BSE::Permissions;
  $self->{perms} ||= BSE::Permissions->new($self->cfg);
  return $self->{perms}->user_has_perm($self->user, $object, $perm, $rmsg);
}

sub DESTROY {
  my ($self) = @_;
  if ($self->{session}) {
    undef $self->{session};
  }
}

1;
