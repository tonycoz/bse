package BSE::Request::Base;
use strict;
use CGI ();
use BSE::Cfg;
use DevHelp::HTML;
use Carp qw(cluck);

sub new {
  my ($class, %opts) = @_;

  BSE::DB->startup();

  $opts{cfg} ||= BSE::Cfg->new;
  $opts{cgi} ||= $class->_make_cgi;
  $opts{fastcgi} ||= 0;

  my $self = bless \%opts, $class;
  if ($self->cfg->entry('html', 'utf8decodeall')) {
    $self->_encode_utf8();
  }
  elsif ($self->cfg->entry('html', 'ajaxcharset', 0)
      && (() = $self->cgi->param('_'))) {
    # convert the values of each parameter from UTF8 to iso-8859-1
    $self->_convert_utf8_cgi_to_charset();
  }

  $self;
}

sub _make_cgi {
  CGI->new;
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

sub is_fastcgi {
  $_[0]{fastcgi};
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

sub template_sets {
  my ($self) = @_;

  return () unless $self->access_control;

  my $user = $self->user
    or return;

  return grep $_ ne '', map $_->{template_set}, $user->groups;
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

sub flash {
  my ($self, @msg) = @_;

  my $msg = "@msg";
  my @flash;
  @flash = @{$self->session->{flash}} if $self->session->{flash};
  push @flash, $msg;
  $self->session->{flash} = \@flash;
}

sub message {
  my ($req, $errors) = @_;

  my $msg = '';
  my @lines;
  if ($errors and keys %$errors) {
    my @fields = $req->cgi->param;
    my %work = %$errors;
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
  }
  if ($req->session->{flash}) {
    push @lines, @{$req->session->{flash}};
    delete $req->session->{flash};
  }
  $msg = join "<br />", map escape_html($_), @lines;
  if (!$msg && $req->cgi->param('m')) {
    $msg = join(' ', $req->cgi->param('m'));
    $msg = escape_html($msg);
  }

  return $msg;
}

sub dyn_response {
  my ($req, $template, $acts) = @_;

  my @search = $template;
  my $base_template = $template;
  my $t = $req->cgi->param('t');
  $t or $t = $req->cgi->param('_t');
  if ($t && $t =~ /^\w+$/) {
    $template .= "_$t";
    unshift @search, $template;
  }

  require BSE::Template;
  my @sets;
  if ($template =~ m!^admin/!) {
    @sets = $req->template_sets;
  }

  return BSE::Template->get_response($template, $req->cfg, $acts,
				     $base_template, \@sets);
}

sub response {
  my ($req, $template, $acts) = @_;

  require BSE::Template;
  my @sets;
  if ($template =~ m!^admin/!) {
    @sets = $req->template_sets;
  }

  return BSE::Template->get_response($template, $req->cfg, $acts, 
				     $template, \@sets);
}

# get the current site user if one is logged on
sub siteuser {
  my ($req) = @_;

  ++$req->{siteuser_calls};
  if (exists $req->{_siteuser}) {
    ++$req->{siteuser_cached};
    return $req->{_siteuser};
  }

  my $cfg = $req->cfg;
  my $session = $req->session;
  require SiteUsers;
  if ($cfg->entryBool('custom', 'user_auth')) {
    require BSE::CfgInfo;
    my $custom = BSE::CfgInfo::custom_class($cfg);

    return $custom->siteuser_auth($session, $req->cgi, $cfg);
  }
  else {
    $req->{_siteuser} = undef;

    my $userid = $session->{userid}
      or return;
    my $user = SiteUsers->getBy(userId=>$userid)
      or return;
    $user->{disabled}
      and return;

    $req->{_siteuser} = $user;

    return $user;
  }
}

sub validate {
  my ($req, %options) = @_;

  $options{rules} ||= {};

  require BSE::Validate;
  BSE::Validate::bse_validate($req->cgi, $options{errors},
			      { 
			       fields => $options{fields},
			       rules => $options{rules},
			      },
			      $req->cfg, $options{section});
}

sub validate_hash {
  my ($req, %options) = @_;

  $options{rules} ||= {};

  require BSE::Validate;
  BSE::Validate::bse_validate_hash($options{data}, $options{errors},
				   { 
				    fields=>$options{fields},
				    rules => $options{rules},
				   },
				   $req->cfg, $options{section});
}

sub configure_fields {
  my ($self, $fields, $section) = @_;

  my $cfg = $self->cfg;
  require BSE::Validate;
  my $cfg_fields = BSE::Validate::bse_configure_fields($fields, $cfg, $section);

  for my $name (keys %$fields) {
    for my $cfg_name (qw/htmltype type width height size maxlength/) {
      my $value = $cfg->entry($section, "${name}_${cfg_name}");
      defined $value and $cfg_fields->{$name}{$cfg_name} = $value;
    }
  }

  $cfg_fields;
}

sub _have_group_access {
  my ($req, $user, $group_ids, $membership) = @_;

  if (grep $_ > 0, @$group_ids) {
    $membership->{filled}
      or %$membership = map { $_ => 1 } 'filled', $user->group_ids;
    return 1
      if grep $membership->{$_}, @$group_ids;
  }
  for my $query_id (grep $_ < 0, @$group_ids) {
    require BSE::TB::SiteUserGroups;
    my $group = BSE::TB::SiteUserGroups->getQueryGroup($req->cfg, $query_id)
      or next;
    my $rows = BSE::DB->single->dbh->selectall_arrayref($group->{sql}, { MaxRows=>1 }, $user->{id});
    $rows && @$rows
      and return 1;
  }

  return 0;
}

sub _siteuser_has_access {
  my ($req, $article, $user, $default, $membership) = @_;

  defined $default or $default = 1;
  defined $membership or $membership = {};

  unless ($article) {
    # this shouldn't happen
    cluck("_siteuser_has_access() called without an article parameter!");
    return 0;
  }

  my @group_ids = $article->group_ids;
  if ($article->{inherit_siteuser_rights}
      && $article->{parentid} != -1) {
    if (@group_ids) {
      $user ||= $req->siteuser
	or return 0;
      if ($req->_have_group_access($user, \@group_ids, $membership)) {
	return 1;
      }
      else {
	return $req->siteuser_has_access($article->parent, $user, 0);
      }
    }
    else {
      # ask parent
      return $req->siteuser_has_access($article->parent, $user, $default);
    }
  }
  else {
    if (@group_ids) {
      $user ||= $req->siteuser
	or return 0;
      if ($req->_have_group_access($user, \@group_ids, $membership)) {
	return 1;
      }
      else {
	return 0;
      }
    }
    else {
      return $default;
    }
  }
}

sub siteuser_has_access {
  my ($req, $article, $user, $default, $membership) = @_;

  $user ||= $req->siteuser;

  ++$req->{has_access_total};
  if ($req->{_siteuser} && $user && $user->{id} == $req->{_siteuser}{id}
      && exists $req->{_access_cache}{$article->{id}}) {
    ++$req->{has_access_cached};
    return $req->{_access_cache}{$article->{id}};
  }

  my $result = $req->_siteuser_has_access($article, $user, $default, $membership);

  if ($user && $req->{_siteuser} && $user->{id} == $req->{_siteuser}{id}) {
    $req->{_access_cache}{$article->{id}} = $result;
  }

  return $result;
}

sub dyn_user_tags {
  my ($self) = @_;

  require BSE::Util::DynamicTags;
  return BSE::Util::DynamicTags->new($self)->tags;
}

sub DESTROY {
  my ($self) = @_;

  if ($self->{cache_stats}) {
    print STDERR "Siteuser cache: $self->{siteuser_calls} Total, $self->{siteuser_cached} Cached\n"
      if $self->{siteuser_calls};
    print STDERR "Access cache: $self->{has_access_total} Total, $self->{has_access_cached} Cached\n"
      if $self->{has_access_total};
  }

  if ($self->{session}) {
    undef $self->{session};
  }
}

sub set_article {
  my ($self, $name, $article) = @_;

  if ($article) {
    $self->{articles}{$name} = $article;
  }
  else {
    delete $self->{articles}{$name};
  }
}

sub get_article {
  my ($self, $name) = @_;

  exists $self->{articles}{$name}
    or return;

  my $article = $self->{articles}{$name};
  if (ref $article eq 'SCALAR') {
    $article = $$article;
  }
  $article 
    or return;

  $article;
}

sub text {
  my ($self, $id, $default) = @_;

  $default;
}

sub _convert_utf8_cgi_to_charset {
  my ($self) = @_;

  require Encode;
  my $cgi = $self->cgi;
  my $workset = $self->cfg->entry('html', 'charset', 'iso-8859-1');
  my $decoded = $self->cfg->entry('html', 'cgi_decoded', 1);
  
  # avoids param decoding the data
  $cgi->charset($workset);

  print STDERR "Converting parameters from UTF8 to $workset\n"
    if $self->cfg->entry('debug', 'convert_charset');

  if ($decoded) {
    # CGI.pm has already converted it from utf8 to perl's internal encoding
    # so we just need to encode to the working encoding
    # I don't see a reliable way to detect this without configuring it
    for my $name ($cgi->param) {
      my @values = map Encode::encode($workset, $_), $cgi->param($name);

      $cgi->param($name => @values);
    }
  }
  else {
    for my $name ($cgi->param) {
      my @values = $cgi->param($name);
      Encode::from_to($_, $workset, 'utf8') for @values;
      $cgi->param($name => @values);
    }
  }
}

sub _encode_utf8 {
  my ($self) = @_;

  my $cgi = $self->cgi;

  require Encode;
  for my $name ($cgi->param) {
    my @values = map Encode::encode('utf8', $_), $cgi->param($name);
    $cgi->param($name => @values);
  }
}

1;
