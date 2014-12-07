package BSE::Request::Base;
use strict;
use CGI ();
use BSE::Cfg;
use BSE::Util::HTML;
use Carp qw(cluck confess);

our $VERSION = "1.030";

=head1 NAME

BSE::Request::Base - base class for request objects

=head1 SYNOPSIS

  use BSE::Request;
  my $req = BSE::Request->new;

=head1 DESCRIPTION

The BSE::Request::Base class provides most of the functionality of
BSE::Request.

=head1 CONSTRUCTOR

=over

=item new()

Create a new request.  Paramaters:

=over

=item *

C<cgi> - provide a custom CGI object.  Default: create a CGI.pm object.

=item *

C<cfg> - provide a custom config object.  Default: create a BSE::Cfg
object.

=item *

C<fastcgi> - set to true and supply cgi if this is a FastCGI request.

=item *

C<nodatabase> - skip database initialization.

=item *

C<nosession> - don't allow a session object to be initialized.

=back

=cut

sub new {
  my ($class, %opts) = @_;

  $opts{cfg} ||= BSE::Cfg->new;

  unless ($opts{nodatabase}) {
    require BSE::DB;
    BSE::DB->init($opts{cfg});
    BSE::DB->startup();
    require Squirrel::Table;
    Squirrel::Table->caching(0);
  }

  my $self = bless \%opts, $class;

  $opts{cgi} ||= $self->_make_cgi;
  $opts{fastcgi} ||= 0;
  $opts{vars} = {};

  return $self;
}

sub _tracking_uploads {
  my ($self) = @_;
  unless (defined $self->{_tracking_uploads}) {
    my $want_track = $self->cfg->entry("basic", "track_uploads", 0);
    my $will_track = $self->_cache_available && $want_track;
    if ($want_track && !$will_track) {
      print STDERR "** Upload tracking requested but no cache found\n";
    }
    $self->{_tracking_uploads} = $will_track;
  }

  return $self->{_tracking_uploads};
}

sub _cache_available {
  my ($self) = @_;

  unless (defined $self->{_cache_available}) {
    my $cache_class = $self->cfg->entry("cache", "class");
    $self->{_cache_available} = defined $cache_class;
  }

  return $self->{_cache_available};
}

sub _cache_object {
  my ($self) = @_;

  $self->_cache_available or return;
  $self->{_cache} and return $self->{_cache};

  require BSE::Cache;

  $self->{_cache} = BSE::Cache->load($self->cfg);

  return $self->{_cache};
}

=back

=head1 METHODS

=over

=item cache_set($key, $value)

Set the cache entry $key to $value.

Does nothing if the cache is not configured.

=cut

sub cache_set {
  my ($self, $key, $value) = @_;

  my $cache = $self->_cache_object
    or return;

  $cache->set($key, $value);
}

=item cache_get($key)

Retrieve the cache entry identified by $key.

=cut

sub cache_get {
  my ($self, $key) = @_;

  my $cache = $self->_cache_object
    or return;

  return $cache->get($key);
}

sub _make_cgi {
  my ($self) = @_;

  my $cache;
  if ($self->_tracking_uploads
      && $ENV{REQUEST_METHOD} eq 'POST'
      && $ENV{CONTENT_TYPE}
      && $ENV{CONTENT_TYPE} =~ m(^multipart/form-data)
      && $ENV{CONTENT_LENGTH}
      && $ENV{QUERY_STRING}
      && $ENV{QUERY_STRING} =~ /^_upload=([a-zA-Z0-9_]+)$/
      && defined ($cache = $self->_cache_object)) {
    # very hacky
    my $upload_key = $1;
    my $fullkey = "upload-$upload_key";
    my $q;
    my $done = 0;
    my $last_set = time();
    my $complete = 0;
    eval {
      $q = CGI->new
	(
	 sub {
	   my ($filename, $data, $size_so_far) = @_;

	   $done += length $data;
	   my $now = time;
	   if ($last_set + 1 <= $now) { # just in case we end up loading Time::HiRes
	     $cache->set($fullkey, 
			 { 
			  done => $done,
			  total => $ENV{CONTENT_LENGTH},
			  filename => $filename,
			  complete => 0 
			 });
	     $last_set = $now;
	   }
	 },
	 0, # data for upload hook
	 1, # continue to use temp files
	 {} # start out empty and don't read STDIN
	);
      
      $q->init(); # initialize for real cgi
      $complete = 1;
    };

    if ($complete) {
      $cache->set($fullkey,
		  {
		   done => $ENV{CONTENT_LENGTH},
		   total => $ENV{CONTENT_LENGTH},
		   complete => 1,
		  });
    }
    else {
      $cache->set($fullkey,
		  {
		   failed => 1,
		  });
      die;
    }

    if ($self->utf8) {
      require BSE::CGI;
      return BSE::CGI->new($q, $self->charset);
    }

    return $q;
  }

  my $q = CGI->new;
  my $error = $q->cgi_error;
  if ($error) {
    print STDERR "CGI ERROR: $error\n";
  }

  if ($self->utf8) {
    require BSE::CGI;
    return BSE::CGI->new($q, $self->charset);
  }

  return $q;
}

=item cgi

Return the request's CGI object.

=cut

sub cgi {
  return $_[0]{cgi};
}

=item cfg

Return the request's cfg object.

=cut

sub cfg {
  return $_[0]{cfg};
}

=item session

Return the request's session object.

=cut

sub session {
  my $self = shift;

  $self->{session}
    or $self->_make_session;

  return $self->{session};
}

=item is_fastcgi

return true for a fast CGI request.

=cut

sub is_fastcgi {
  $_[0]{fastcgi};
}

=item end_request

End the current request.

Must only be called by BSE itself.

=cut

sub end_request {
  delete $_[0]{session};
}

=item user

Return the currently logged in admin user.

Only valid in administrative templates.

=cut

sub user {
  return $_[0]{adminuser};
}

sub setuser {
  $_[0]{adminuser} = $_[1];
}

sub getuser {
  $_[0]{adminuser};
}

=item url($action, $params, $name)

Equivalent to $req->cfg->admin_url($action, $params, $name)

=cut

sub url {
  my ($self, $action, $params, $name) = @_;

  return $self->cfg->admin_url($action, $params, $name);
}

=item check_admin_logon()

Used internally to check an admin user is logged on.

=cut

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
   generator => 'BSE::Generate::Article',
   level     => 0,
  };

=item user_can($perm, $object, $msg)

Check if the current admin user can perform action $perm on $object.

$object is an article or an article id.

=cut

sub user_can {
  my ($self, $perm, $object, $rmsg) = @_;

  require BSE::Permissions;
  $object ||= $site_article;
  $self->{perms} ||= BSE::Permissions->new($self->cfg);
  if ($self->cfg->entry('basic', 'access_control', 0)) {
    unless (ref $object) {
      require BSE::TB::Articles;
      my $art = $object == -1 ? $site_article : BSE::TB::Articles->getByPkey($object);
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

=item access_control

Return true if access control is enabled.

=cut

sub access_control {
  $_[0]->{cfg}->entry('basic', 'access_control', 0);
}

=item flash($msg, ...)

Flash a notice (backward compat).

=cut

sub flash {
  my ($self, @msg) = @_;

  return $self->flash_notice(@msg);
}

=item flash_error($msg, ...)

Flash an error message.

=cut

sub flash_error {
  my ($self, @msg) = @_;

  return $self->flashext({ class => "error" }, @msg);
}

=item flash_notice($msg, ...)

Flash a notice.

=cut

sub flash_notice {
  my ($self, @msg) = @_;

  return $self->flashext({ class => "notice" }, @msg);
}

=item flashext(\%opts, $msg, ...)

Flash a message, with options.

Possible options are:

=over

=item *

class - defaults to "notice".

=item *

type - defaults to "text", can also be "html".

=back

The $msg parameter can also be a message id.

=cut

sub flashext {
  my ($self, $opts, @msg) = @_;

  my %entry =
    (
     class => $opts->{class} || "notice",
     type => "text",
    );
  if ($msg[0] =~ /^msg:/) {
    $entry{text} = $self->catmsg(@msg);
    $entry{html} = $self->htmlmsg(@msg);
  }
  else {
    $entry{text} = "@msg";
    $entry{html} = escape_html($entry{text});
  }

  my @flash;
  @flash = @{$self->session->{flash}} if $self->session->{flash};
  push @flash, \%entry;

  $self->session->{flash} = \@flash;
}

sub _str_msg {
  my ($req, $msg) = @_;

  if ($msg =~ /^(msg:[\w-]+(?:\/[\w-]+)+)(?::(.*))?$/) {
    my $id = $1;
    my $params = $2;
    my @params = defined $params ? split(/:/, $params) : ();
    $msg = $req->catmsg($id, \@params);
  }

  return $msg;
}

sub _str_msg_html {
  my ($req, $msg) = @_;

  if ($msg =~ /^(msg:[\w-]+(?:\/[\w-]+)+)(?::(.*))?$/) {
    my $id = $1;
    my $params = $2;
    my @params = defined $params ? split(/:/, $params) : ();
    $msg = $req->htmlmsg($id, \@params);
  }
  else {
    $msg = escape_html($msg);
  }

  return $msg;
}

=item messages($errors)

Retrieve the current set of messages, optionally setting them.

Returns a list of message entries, each with:

=over

=item *

class - error or notice.

=item *

type - the original content type of the message, either "text" or
"html".

=item *

text - the message as text.

=item *

html - the message as html.

=back

=cut

sub messages {
  my ($self, $errors) = @_;

  my @messages;
  push @messages, @{$self->{messages}} if $self->{messages};
  if ($errors and ref $errors && keys %$errors) {
    # do any translation needed
    for my $key (keys %$errors) {
      my @msgs = ref $errors->{$key} ? @{$errors->{$key}} : $errors->{$key};

      for my $msg (@msgs) {
	$msg = $self->_str_msg($msg);
      }
      $errors->{$key} = ref $errors->{$key} ? \@msgs : $msgs[0];
    }

    my @fields = $self->cgi->param;
    my %work = %$errors;
    for my $field (@fields) {
      if (my $entry = delete $work{$field}) {
	push @messages,
	  map +{
		type => "text",
		text => $_,
		class => "error",
		html => escape_html($_),
	       }, ref($entry) ? grep $_, @$entry : $entry;
      }
    }
    for my $entry (values %work) {
      if (ref $entry) {
	push @messages, map
	  +{
	    type => "text",
	    text => $_,
	    class => "error",
	    html => escape_html($_)
	   }, grep $_, @$entry;
      }
      else {
	push @messages,
	  {
	   type => "text",
	   text => $entry,
	   class => "error",
	   html => escape_html($entry),
	  };
      }
    }
    $self->{field_errors} = $errors;
  }
  elsif ($errors && !ref $errors) {
    push @messages,
      {
       type => "text",
       text => $errors,
       class => "error",
       html => escape_html($errors),
      };
  }
  if (!$self->{nosession} && $self->session->{flash}) {
    push @messages, @{$self->session->{flash}};
    delete $self->session->{flash};
  }
  if (!@messages && $self->cgi->param('m')) {
    push @messages, map
      +{
	type => "text",
	text => $self->_str_msg($_),
	class => "unknown",
	html => $self->_str_msg_html($_),
       }, $self->cgi->param("m");
  }

  my %seen;
  @messages = grep !$seen{$_->{html}}++, @messages; # don't need duplicates

  $self->{messages} = \@messages;

  return \@messages;
}

=item message($errors)

Return the current set of messages as a single string in HTML, with
C<< <br /> >> separators.

=cut

sub message {
  my ($self, $errors) = @_;

  my $messages = $self->messages($errors);

  return join "<br />",
    map { $_->{type} eq 'html' ? $_->{text} : escape_html($_->{text}) } @$messages
}

=item field_errors

Return a hash of field errors that have been supplied to
message()/messages().

=cut

sub field_errors {
  my ($self) = @_;

  return $self->{field_errors} || {};
}

sub _set_vars {
  my ($self) = @_;

  require Scalar::Util;
  $self->{vars}{request} = $self;
  Scalar::Util::weaken($self->{vars}{request});
  $self->set_variable(cgi => $self->cgi);
  $self->set_variable(cfg => $self->cfg);
  $self->set_variable(assert_dynamic => 1);
  unless ($self->{vars}{bse}) {
    require BSE::Variables;
    $self->set_variable(bse => BSE::Variables->dyn_variables(request => $self));
  }
}

=item siteuser

Get the currently logged in siteuser.

=cut

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
  require BSE::TB::SiteUsers;
  if ($cfg->entryBool('custom', 'user_auth')) {
    require BSE::CfgInfo;
    my $custom = BSE::CfgInfo::custom_class($cfg);

    return $custom->siteuser_auth($session, $req->cgi, $cfg);
  }
  else {
    $req->{_siteuser} = undef;

    my $userid = $session->{userid}
      or return;
    my $user = BSE::TB::SiteUsers->getByPkey($userid)
      or return;
    $user->{disabled}
      and return;

    $req->{_siteuser} = $user;

    return $user;
  }
}

=item validate()

Perform data validation on the current CGI request.  Parameters include:

=over

=item *

errors

=item *

fields

=item *

rules

=item *

section

=item *

optional

=back

=cut

sub validate {
  my ($req, %options) = @_;

  $options{rules} ||= {};

  require BSE::Validate;
  my %opts =
    (
     fields => $options{fields},
     rules => $options{rules},
    );
  exists $options{optional} and $opts{optional} = $options{optional};
  BSE::Validate::bse_validate
      (
       $req->cgi,
       $options{errors},
       \%opts,
       $req->cfg,
       $options{section}
      );
}

=item validate_hash(%opts)

Validate data stored in a hash.

Takes an extra parameter over L</validate()>:

=over

=item *

data - a hash reference with the data to validate.

=back

=cut

sub validate_hash {
  my ($req, %options) = @_;

  $options{rules} ||= {};

  my %opts =
    (
     fields => $options{fields},
     rules => $options{rules},
    );
  exists $options{optional} and $opts{optional} = $options{optional};
  require BSE::Validate;
  BSE::Validate::bse_validate_hash
      (
       $options{data},
       $options{errors},
       \%opts,
       $req->cfg,
       $options{section}
      );
}

=item configure_fields(\%fields, $section)

Configure a field hash.

=cut

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

sub _article_parent {
  my ($self, $article) = @_;

  my $id = $article->parentid;
  $id > 0
    or return;

  $self->{_cached_article} ||= {};
  my $cache = $self->{_cached_article};

  $cache->{$id}
    or $cache->{$id} = $article->parent;

  return $cache->{$id};
}

sub _article_group_ids {
  my ($self, $article) = @_;

  my $id = $article->id;
  $self->{_cached_groupids} ||= {};
  my $cache = $self->{_cached_groupids};
  $cache->{$id}
    or $cache->{$id} = [ $article->group_ids ];

  return @{$cache->{$id}};
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

  my @group_ids = $req->_article_group_ids($article);
  if ($article->{inherit_siteuser_rights}
      && $article->{parentid} != -1) {
    if (@group_ids) {
      $user ||= $req->siteuser
	or return 0;
      if ($req->_have_group_access($user, \@group_ids, $membership)) {
	return 1;
      }
      else {
	return $req->siteuser_has_access($req->_article_parent($article), $user, 0);
      }
    }
    else {
      # ask parent
      return $req->siteuser_has_access($req->_article_parent($article), $user, $default);
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

=item siteuser_has_access($article)

=item siteuser_has_access($article, $user)

Check if the current or supplied site user has access to the supplied article.

=cut

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

  $self->set_variable($name, $article);
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

sub set_variable {
  my ($self, $name, $value) = @_;

  $self->{vars}{$name} = $value;
}

sub set_variable_class {
  my ($self, $name, $class) = @_;

  require Squirrel::Template;
  $self->set_variable($name => Squirrel::Template::Expr::WrapClass->new($class));
}

sub text {
  my ($self, $id, $default) = @_;

  return $self->cfg->entry('messages', $id, $default);
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

sub user_url {
  my ($req, $script, $target, @options) = @_;

  return $req->cfg->user_url($script, $target, @options);
}

=item is_ssl

Return true if the current request is an SSL request.

=cut

sub is_ssl {
  exists $ENV{HTTPS} || exists $ENV{SSL_CIPHER};
}

my %recaptcha_errors = 
  (
   'incorrect-captcha-sol' => 'Incorrect CAPTCHA solution',
   'recaptcha-not-reachable' => "CAPTCHA server not reachable, please wait a moment and try again",
  );

=item test_recaptcha

Test if a valid reCAPTCHA response was received.

=cut

sub test_recaptcha {
  my ($self, %opts) = @_;

  require Captcha::reCAPTCHA;
  my $apiprivkey = $self->cfg->entry('recaptcha', 'api_private_key');
  unless (defined $apiprivkey) {
    print STDERR "** No recaptcha api_private_key defined **\n";
    return;
  }
  my $msg;
  my $error = $opts{error} || \$msg;
  my $c = Captcha::reCAPTCHA->new;
  my $cgi = $self->cgi;
  my $challenge = $cgi->param('recaptcha_challenge_field');
  my $response = $cgi->param('recaptcha_response_field');
  delete $self->{recaptcha_error};
  if (!defined $challenge || $challenge !~ /\S/) {
    $$error = "No reCAPTCHA challenge found";
    return;
  }
  if (!defined $response || $response !~ /\S/) {
    $$error = "No reCAPTCHA response entered";
    return;
  }

  my $result = $c->check_answer($apiprivkey, $ENV{REMOTE_ADDR},
				$challenge, $response);
  unless ($result->{is_valid}) {
    my $key = 'error_'.$result->{error};
    $key =~ tr/-/_/;
    $$error = $self->cfg->entry('recaptcha', $key)
      || $recaptcha_errors{$result->{error}}
	|| $result->{error};
  }
  $self->{recaptcha_result} = $result;

  return !!$result->{is_valid};
}

sub recaptcha_result {
  $_[0]{recaptcha_result};
}

=item get_csrf_token($name)

Generate a csrf token for the given name.

=cut

my $sequence = 0;

sub get_csrf_token {
  my ($req, $name) = @_;

  my $cache = $req->session->{csrfp};
  my $max_age = $req->cfg->entry('basic', 'csrfp_max_age', 3600);
  my $now = time;
  
  my $entry = $cache->{$name};
  if (!$entry || $entry->{time} + $max_age < $now) {
    if ($entry) {
      $entry->{oldtoken} = $entry->{token};
      $entry->{oldtime} = $entry->{time};
    }
    else {
      $entry = {};
    }

    # this doesn't need to be so perfectly secure that we drain the
    # entropy pool and it'll be called fairly often
    require Digest::MD5;
    $entry->{token} =
      Digest::MD5::md5_hex($now . $$ . rand() . $sequence++ . $name);
    $entry->{time} = $now;
  }
  $cache->{$name} = $entry;
  $req->session->{csrfp} = $cache;

  return $entry->{token};
}

=item check_csrf($name)

Check if the CSRF token supplied by the form is valid.

$name should be the name supplied to the csrfp token.

=cut

sub check_csrf {
  my ($self, $name) = @_;

  defined $name
    or confess "No CSRF token name supplied";

  $self->is_ajax
    and return 1;

  my $debug = $self->cfg->entry('debug', 'csrf', 0);

  # the form might have multiple submit buttons, each initiating a
  # different function, so the the form should supply tokens for every
  # function for the form
  my @tokens = $self->cgi->param('_csrfp');
  unless (@tokens) {
    $self->_csrf_error("No _csrfp token supplied");
    return;
  }

  my $entry = $self->session->{csrfp}{$name};
  unless ($entry) {
    $self->_csrf_error("No token entry found for $name");
    return;
  }
  
  my $max_age = $self->cfg->entry('basic', 'csrfp_max_age', 3600);
  my $now = time;
  for my $token (@tokens) {
    if ($entry->{token} 
	&& $entry->{token} eq $token
	&& $entry->{time} + 2*$max_age >= $now) {
      $debug
	and print STDERR "CSRF: match current token\n";
      return 1;
    }

    if ($entry->{oldtoken}
	&& $entry->{oldtoken} eq $token
	&& $entry->{oldtime} + 2*$max_age >= $now) {
      return 1;
    }
  }

  $self->_csrf_error("No tokens matched the $name entry");
  return;
}

sub _csrf_error {
  my ($self, $message) = @_;

  $self->cfg->entry('debug', 'csrf', 0)
    and print STDERR "csrf error: $message\n";
  $self->{csrf_error} = $message;

  return;
}

sub csrf_error {
  $_[0]{csrf_error};
}

=item audit(object => $object, action => $action)

Simple audit logging.

See BSE::TB::AuditLog.

object, component, msg are required.

=cut

sub audit {
  my ($self, %opts) = @_;

  require BSE::TB::AuditLog;

  $opts{actor} ||= $self->user || "U";

  return BSE::TB::AuditLog->log(%opts);
}

sub utf8 {
  my $self = shift;
  return $self->cfg->utf8;
}

sub charset {
  my $self = shift;
  return $self->cfg->charset;
}

=item message_catalog

Retrieve the message catalog.

=cut

sub message_catalog {
  my ($self) = @_;

  unless ($self->{message_catalog}) {
    require BSE::Message;
    my %opts;
    $self->_cache_available and $opts{cache} = $self->_cache_object;
    $self->{message_catalog} = BSE::Message->new(%opts);
  }

  return $self->{message_catalog};
}

=item catmsg($id)

=item catmsg($id, \@params)

=item catmsg($id, \@params, $default)

=item catmsg($id, \@params, $default, $lang)

Retrieve a message from the message catalog, performing substitution.

This retrieves the text version of the message only.

=cut

sub catmsg {
  my ($self, $id, $params, $default, $lang) = @_;

  defined $lang or $lang = $self->language;
  defined $params or $params = [];

  $id =~ s/^msg://
    or return "* bad message id - missing leading msg: *";

  my $result = $self->message_catalog->text($lang, $id, $params, $default);
  unless ($result) {
    $result = "Unknown message id $id";
  }

  return $result;
}

=item htmlmsg($id)

=item htmlmsg($id, \@params)

=item htmlmsg($id, \@params, $default)

=item htmlmsg($id, \@params, $default, $lang)

Retrieve a message from the message catalog, performing substitution.

This retrieves the html version of the message only.

=cut

sub htmlmsg {
  my ($self, $id, $params, $default, $lang) = @_;

  defined $lang or $lang = $self->language;
  defined $params or $params = [];

  $id =~ s/^msg://
    or return "* bad message id - missing leading msg: *";

  my $result = $self->message_catalog->html($lang, $id, $params, $default);
  unless ($result) {
    $result = "Unknown message id $id";
  }

  return $result;
}

=item language

Fetch the language for the current system/user.

Warning: this currently fetches a system configured default, in the
future it will use a user default and/or a browser set default.

=cut

sub language {
  my ($self) = @_;

  return $self->cfg->entry("basic", "language_code", "en");
}

=item ip_address

The IP address of the broswer.

=cut

sub ip_address {
  return $ENV{REMOTE_ADDR};
}

=item method

The request method (post, get etc) in lower case

=cut

sub method {
  return lc $ENV{REQUEST_METHOD};
}

=item user_agent

The browser user agent string.

=cut

sub user_agent {
  return $ENV{HTTP_USER_AGENT} || "";
}

=item referer

The referer if any.

=cut

sub referer {
  return $ENV{HTTP_REFERER} || "";
}

=item cart

The user's shopping cart as a L<BSE::Cart> object.

=cut

sub cart {
  my ($self, $stage) = @_;

  require BSE::Cart;
  $self->{cart} ||= BSE::Cart->new($self, $stage);

  return $self->{cart};
}

=back

=head2 Page Generation

These aren't suitable for use in a template.

=over

=item template_sets()

Return a list of template sets for the current admin user.

=cut

sub template_sets {
  my ($self) = @_;

  return () unless $self->access_control;

  my $user = $self->user
    or return;

  return grep $_ ne '', map $_->{template_set}, $user->groups;
}

=item get_refresh($url)

Fetch a refresh result for the given url.

=cut

sub get_refresh {
  my ($req, $url) = @_;

  require BSE::Template;
  BSE::Template->get_refresh($url, $req->cfg);
}

=item get_def_refresh($url)

Fetch a refresh based on the C<r> cgi parameter or the provided url if
C<r> isn't set.

=cut

sub get_def_refresh {
  my ($req, $url) = @_;

  my $r = $req->cgi->param("r");
  $r ||= $url;

  return $req->get_refresh($r);
}

=item output_result($result)

Output a page result.

=cut

sub output_result {
  my ($req, $result) = @_;

  require BSE::Template;
  BSE::Template->output_result($req, $result);
}

=item dyn_response($template, $acts, $modifier)

=item dyn_response($template, $acts)

Generate a page result from template with the given tags.

Allows _t or t to specify an alternate template.

=cut

sub dyn_response {
  my ($req, $template, $acts, $modifier) = @_;

  my @search = $template;
  my $base_template = $template;
  my $t = $req->cgi->param('t');
  $t or $t = $req->cgi->param('_t');
  $t or $t = $modifier;
  if ($t && $t =~ /^\w+$/) {
    $template .= "_$t";
    unshift @search, $template;
  }

  $req->set_variable(template => $template);
  $req->_set_vars();

  require BSE::Template;
  my @sets;
  if ($template =~ m!^admin/!) {
    @sets = $req->template_sets;
  }

  return BSE::Template->get_response($template, $req->cfg, $acts,
				     $base_template, \@sets, $req->{vars},
				     dynamic => 1);
}

=item response($template, $acts)

Return a page response generated from $template and the tags in $acts.

=cut

sub response {
  my ($req, $template, $acts) = @_;

  require BSE::Template;
  my @sets;
  if ($template =~ m!^admin/!) {
    @sets = $req->template_sets;
  }

  $req->set_variable(template => $template);
  $req->_set_vars();

  return BSE::Template->get_response($template, $req->cfg, $acts, 
				     $template, \@sets, $req->{vars},
				     dynamic => 1);
}

=item dyn_user_tags()

Return the standard dynamic page tags.

=cut

sub dyn_user_tags {
  my ($self) = @_;

  require BSE::Util::DynamicTags;
  return BSE::Util::DynamicTags->new($self)->tags;
}

=item admin_tags()

Return the standard admin page tags.

=cut

sub admin_tags {
  my ($req) = @_;

  $req->set_variable
    (
     auditlog =>
     sub {
       require BSE::TB::AuditLog;
       Squirrel::Template::Expr::WrapClass->new("BSE::TB::AuditLog")
     });

  require BSE::Util::Tags;
  return
    (
     BSE::Util::Tags->common($req),
     BSE::Util::Tags->admin(undef, $req->cfg),
     BSE::Util::Tags->secure($req),
     $req->custom_admin_tags,
    );
}

sub custom_admin_tags {
  my ($req) = @_;

  $req->cfg->entry("custom", "admin_tags")
    or return;

  require BSE::CfgInfo;

  return BSE::CfgInfo::custom_class($req->cfg)->admin_tags($req);
}

=item is_ajax

Return true if the current request is an Ajax request.

Warning: changing this code has security concerns, it should only
match where the request can only be an Ajax request - if the request
can be produced by a normal form/link POST or GET this method must NOT
return true.

=cut

sub is_ajax {
  my ($self) = @_;

  defined $ENV{HTTP_X_REQUESTED_WITH}
    && $ENV{HTTP_X_REQUESTED_WITH} =~ /XMLHttpRequest/
      and return 1;

  return;
}

=item want_json_response

Return true if the caller has indicated they want a JSON response.

In practice, returns true if is_ajax() is true or a _ parameter was
supplied.

=cut

sub want_json_response {
  my ($self) = @_;

  $self->is_ajax and return 1;

  $self->cgi->param("_") and return 1;

  return;
}

=item send_email

Send a simple email.

=cut

sub send_email {
  my ($self, %opts) = @_;

  my $acts = $opts{acts} || {};
  my %acts =
    (
     $self->dyn_user_tags,
     %$acts,
    );
  if ($opts{extraacts}) {
    %acts = ( %acts, %{$opts{extraacts}} );
  }
  require BSE::ComposeMail;
  return BSE::ComposeMail->send_simple
    (
     %opts,
     acts => \%acts
    );
}

=item json_content

Generate a hash suitable for output_result() as JSON.

=cut

sub json_content {
  my ($self, @values) = @_;

  require JSON;

  my $json = JSON->new;

  if ($self->utf8) {
    $json->utf8;
  }

  my $value = @values > 1 ? +{ @values } : $values[0];
  my ($context) = $self->cgi->param("_context");
  if (defined $context) {
    $value->{context} = $context;
  }

  my $json_result =
    +{
      type => "application/json",
      content => $json->encode($value),
     };

  if (!exists $ENV{HTTP_X_REQUESTED_WITH}
      || $ENV{HTTP_X_REQUESTED_WITH} !~ /XMLHttpRequest/) {
    $json_result->{type} = "text/plain";
  }

  return $json_result;
}

sub field_error {
  my ($self, $errors) = @_;

  my %errors = %$errors;
  for my $key (keys %errors) {
    if ($errors{$key} =~ /^msg:/) {
      $errors{$key} = $self->_str_msg($errors{$key});
    }
  }

  return $self->json_content
    (
     success => 0,
     error_code => "FIELD",
     errors => \%errors,
     message => "Fields failed validation",
    );
}

=item logon_error

Standard structure of an "admin user not logged on" error returned as
JSON content.

=cut

sub logon_error {
  my ($self) = @_;
  return $self->json_content
    (
     success => 0,
     error_code => "LOGON",
     message => "Access forbidden: user not logged on",
     errors => {},
    );
}

=item cgi_fields

Extract values for the fields specified by the fields parameter.

Field information expected or supported:

=over

=item *

C<htmltype> - if this is checkbox, C<type> is consulted, if C<"int">
then set the value based on whether the field is present, otherwise
return a concatenation of the values of the checkboxes of that name.

=item *

C<type> - if C<date> then parse the content as a date.

=item *

C<api> - if true, don't convert dates from d/m/y to y-m-d, since they
should already be that format.

=item *

C<trim> - for plain text fields, trim leading and trailing whitespace.

=item *

C<readonly> - no values are stored.

=back

=cut

sub cgi_fields {
  my ($self, %opts) = @_;

  my %values;
  my $fields = $opts{fields}
    or confess "Missing fields parameter";

  my $cgi = $self->cgi;
 FIELD:
  for my $name (keys %$fields) {
    my $field = $fields->{$name};
    $field->{readonly}
      and next FIELD;
    my $value;
    if ($field->{htmltype} eq "checkbox") {
      if ($field->{type} eq "int") {
	$value = $cgi->param($name) ? 1 : 0;
      }
      else {
	$value = join("", $cgi->param($name));
      }
    }
    elsif ($field->{htmltype} eq "multicheck") {
      $value = [ $cgi->param($name) ];
    }
    elsif ($field->{type} && $field->{type} eq "date" && !$opts{api}) {
      ($value) = $cgi->param($name);
      require DevHelp::Date;
      my $msg;
      my ($year, $month, $day) = DevHelp::Date::dh_parse_date($value, \$msg);
      $value = sprintf("%04d-%02d-%02d", $year, $month, $day);
    }
    elsif ($field->{type} && $field->{type} eq "time" && !$opts{api}) {
      ($value) = $cgi->param($name);
      require DevHelp::Date;
      my $msg;
      my ($hour, $minute, $sec) = DevHelp::Date::dh_parse_time($value, \$msg);
      $value = sprintf("%02d:%02d:%02d", $hour, $minute, $sec);
    }
    else {
      ($value) = $cgi->param($name);
      defined $name or $value = "";
      if ($field->{trim}) {
	$value =~ s/^\s+//;
	$value =~ s/\s+\z//;
      }
    }
    $values{$name} = $value;
  }

  return \%values;
}

=item ip_locked_out

Return true if there's an active IP address lockout of the current IP
address.

=cut

sub ip_locked_out {
  my ($self, $type) = @_;

  require BSE::TB::IPLockouts;
  return BSE::TB::IPLockouts->active($self->ip_address, $type);
}

1;

=back

=head1 AUTHOR

Tony Cook <tony@develop-help.com>

=cut
