package BSE::Request;
use strict;
use BSE::Session;
use CGI ();
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

sub check_admin_logon {
  my ($self) = @_;

  require BSE::Permissions;
  return BSE::Permissions->check_logon($self);
}


my $site_article = { id=>-1, title=>"unknown", parentid=>0 };

sub user_can {
  my ($self, $perm, $object, $rmsg) = @_;

  require BSE::Permissions;
  $object ||= $site_article;
  $self->{perms} ||= BSE::Permissions->new($self->cfg);
  if ($self->cfg->entry('basic', 'access_control', 0)) {
    unless (ref $object) {
      require Articles;
      my $art = $object == -1 ? $site_article : Articles->getByPkey($object);
      if ($art) {
	$object = $art;
      }
      else {
	print STDERR "** Cannot find article id $object\n";
	require Carp;
	Carp::cluck "Cannot find article id $object";
	return 0;
      }
    }
    return $self->{perms}->user_has_perm($self->user, $object, $perm, $rmsg);
  }
  else {
    # some checks need to happen even if we don't want logons
    return $self->{perms}->user_has_perm({ id=>-1 }, $object, $perm, $rmsg);
  }
}

# a stub for now
sub get_object {
  return;
}

sub access_control {
  $_[0]->{cfg}->entry('basic', 'access_control', 0);
}

sub DESTROY {
  my ($self) = @_;
  if ($self->{session}) {
    undef $self->{session};
  }
}

1;
