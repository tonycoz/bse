package BSE::Request::Base;
use strict;
use CGI ();
use BSE::Cfg;
use DevHelp::HTML;
use Carp qw(cluck confess);

sub new {
  my ($class, %opts) = @_;

  $opts{cfg} ||= BSE::Cfg->new;

  unless ($opts{nodatabase}) {
    require BSE::DB;
    BSE::DB->init($opts{cfg});
    BSE::DB->startup();
  }

  my $self = bless \%opts, $class;

  $opts{cgi} ||= $self->_make_cgi;
  $opts{fastcgi} ||= 0;

  if ($self->cfg->entry('html', 'utf8decodeall')) {
    $self->_encode_utf8();
  }
  elsif ($self->cfg->entry('html', 'ajaxcharset', 0)
      && $self->is_ajax) {
    # convert the values of each parameter from UTF8 to iso-8859-1
    $self->_convert_utf8_cgi_to_charset();
  }

  $self;
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

sub cache_set {
  my ($self, $key, $value) = @_;

  my $cache = $self->_cache_object
    or return;

  $cache->set($key, $value);
}

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
      && defined ($cache = $self->_cache_object)) {
    # very hacky
    my $q;
    my $done = 0;
    my $last_set = time();
    my $upload_key;
    if ($ENV{QUERY_STRING}
	&& $ENV{QUERY_STRING} =~ /^_upload=([a-zA-Z0-9_]+)$/) {
      $upload_key = $1;
    }
    my $complete = 0;
    eval {
      $q = CGI->new
	(
	 sub {
	   my ($filename, $data, $size_so_far) = @_;
	   
	   $upload_key ||= $q->param("_upload");
	   $upload_key or return;
	   my $fullkey = "upload-$upload_key";
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

    if ($upload_key) {
      my $fullkey = "upload-$upload_key";
      
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
    }
 

    return $q;
  }

  my $q = CGI->new;
  my $error = $q->cgi_error;
  if ($error) {
    print STDERR "CGI ERROR: $error\n";
  }

  return $q;
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

sub get_refresh {
  my ($req, $url) = @_;

  require BSE::Template;
  BSE::Template->get_refresh($url, $req->cfg);
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
    # do any translation needed
    for my $key (keys %$errors) {
      my @msgs = ref $errors->{$key} ? @{$errors->{$key}} : $errors->{$key};

      for my $msg (@msgs) {
	if ($msg =~ /^(msg:[\w-]+(?:\/[\w-]+)+)(?::(.*))/) {
	  my $id = $1;
	  my $params = $2;
	  my @params = defined $params ? split(/:/, $params) : ();
	  $msg = $req->catmsg($id, \@params);
	}
      }
      $errors->{$key} = ref $errors->{$key} ? \@msgs : $msgs[0];
    }

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
  if (!$req->{nosession} && $req->session->{flash}) {
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

  my $cfg = $req->cfg;
  my $base = $script eq 'shop' ? $cfg->entryVar('site', 'secureurl') : '';
  my $template;
  if ($target) {
    if ($script eq 'nuser') {
      $template = "/cgi-bin/nuser.pl/user/TARGET";
    }
    else {
      $template = "$base/cgi-bin/$script.pl?a_TARGET=1";
    }
    $template = $cfg->entry('targets', $script, $template);
    $template =~ s/TARGET/$target/;
  }
  else {
    if ($script eq 'nuser') {
      $template = "/cgi-bin/nuser.pl/user";
    }
    else {
      $template = "$base/cgi-bin/$script.pl";
    }
    $template = $cfg->entry('targets', $script.'_n', $template);
  }
  if (@options) {
    $template .= $template =~ /\?/ ? '&' : '?';
    my @entries;
    while (my ($key, $value) = splice(@options, 0, 2)) {
      push @entries, "$key=" . escape_uri($value);
    }
    $template .= join '&', @entries;
  }

  return $template;
}

sub admin_tags {
  my ($req) = @_;

  require BSE::Util::Tags;
  return
    (
     BSE::Util::Tags->common($req),
     BSE::Util::Tags->admin(undef, $req->cfg),
     BSE::Util::Tags->secure($req),
    );
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

  require BSE::ComposeMail;
  my $mailer = BSE::ComposeMail->new(cfg => $self->cfg);

  my $id = $opts{id}
    or confess "No mail id provided";

  my $section = "email $id";

  for my $key (qw/subject template html_template allow_html from from_name/) {
    my $value = $self->{cfg}->entry($section, $key);
    defined $value and $opts{$key} = $value;
  }
  unless (defined $opts{acts}) {
    require BSE::Util::Tags;
    BSE::Util::Tags->import(qw/tag_hash_plain/);
    my %acts =
      (
       $self->dyn_user_tags
      );
    if ($opts{extraacts}) {
      %acts = ( %acts, %{$opts{extraacts}} );
    }
    $opts{acts} = \%acts;
  }

  $mailer->send(%opts)
    or print STDERR "Error sending mail $id: ", $mailer->errstr, "\n";

  return 1;
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

=item json_content

Generate a hash suitable for output_result() as JSON.

=cut

sub json_content {
  my ($self, @values) = @_;

  require JSON;

  my $json = JSON->new;

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

We record:

  object id, object describe result, action, siteuserid, ip address, date/time

object and action are required.

=cut

sub audit {
  my ($self, %opts) = @_;

  my $object = delete $opts{object}
    or confess "Missing object parameter";

  my $action = delete $opts{action}
    or confess "Missing action parameter";

  # check all of these are callable
  my $id = $object->id;
  my $desc = $object->describe;

  $self->cfg->entry("basic", "auditlog", 0)
    or return; # no audit logging

  # assumed that check_admin_logon() has been done
  my $admin = $self->user;

  require BSE::Util::SQL;
  require BSE::TB::AuditLog;
  my %entry =
    (
     object_id => $id,
     object_desc => $desc,
     action => $action,
     admin_id => $admin ? $admin->id : undef,
     ip_address => $ENV{REMOTE_ADDR},
     when_at => BSE::Util::SQL::now_datetime(),
    );
  BSE::TB::AuditLog->make(%entry);
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

=item language

Fetch the language for the current system/user.

Warning: this currently fetches a system configured default, in the
future it will use a user default and/or a browser set default.

=cut

sub language {
  my ($self) = @_;

  return $self->cfg->entry("basic", "language_code", "en");
}

sub ip_address {
  return $ENV{REMOTE_ADDR};
}

1;
