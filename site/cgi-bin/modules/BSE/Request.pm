package BSE::Request;
use strict;
use BSE::Session;
use CGI ();
use BSE::Cfg;
use DevHelp::HTML;

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
  $_[0]{session} or die "Session has been deleted already\n";

  return $_[0]{session};
}

sub end_request {
  delete $_[0]{session};
}

sub extra_headers { return }

sub user {
  return $_[0]{adminuser};
}

sub setuser {
  $_[0]{adminuser} = $_[1];
}

sub getuser {
  $_[0]{adminuser};
}

# this needs to become non-admin specific
sub url {
  my ($self, $action, $params, $name) = @_;

  require BSE::CfgInfo;
  my $url = BSE::CfgInfo::admin_base_url($self->{cfg});
  $url .= "/cgi-bin/admin/$action.pl";
  if ($params && keys %$params) {
    $url .= "?" . join("&", map { "$_=".escape_uri($params->{$_}) } keys %$params);
  }
  $url .= "#$name" if $name;

  $url;
}

sub check_admin_logon {
  my ($self) = @_;

  require BSE::Permissions;
  return BSE::Permissions->check_logon($self);
}


my $site_article = 
  { 
   id        => -1, 
   title     => "unknown", 
   parentid  => 0, 
   generator => 'Generate::Article',
   level     => 0,
  };

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

sub output_result {
  my ($req, $result) = @_;

  require BSE::Template;
  BSE::Template->output_result($req, $result);
}

sub message {
  my ($req, $errors) = @_;

  my $msg = '';
  if ($errors and keys %$errors) {
    my @fields = $req->cgi->param;
    my %work = %$errors;
    my @lines;
    for my $field (@fields) {
      if (my $entry = delete $work{$field}) {
	push @lines, ref($entry) ? grep $_, @$entry : $entry;
      }
    }
    for my $entry (values %work) {
      if (ref $entry) {
	push @lines, grep $_, @$entry;
      }
      else {
	push @lines, $entry;
      }
    }
    my %seen;
    @lines = grep !$seen{$_}++, @lines; # don't need duplicates
    $msg = join "<br />", map escape_html($_), @lines;
  }
  if (!$msg && $req->cgi->param('m')) {
    $msg = join(' ', $req->cgi->param('m'));
    $msg = escape_html($msg);
  }

  return $msg;
}

sub dyn_response {
  my ($req, $template, $acts) = @_;

  my $base_template = $template;
  my $t = $req->cgi->param('t');
  if ($t && $t =~ /^\w+$/) {
    $template .= "_$t";
  }

  return BSE::Template->get_response($template, $req->cfg, $acts,
				    $base_template);
}

sub DESTROY {
  my ($self) = @_;
  if ($self->{session}) {
    undef $self->{session};
  }
}

1;
