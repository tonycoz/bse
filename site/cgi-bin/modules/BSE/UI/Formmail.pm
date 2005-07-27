package BSE::UI::Formmail;
use strict;
use base qw(BSE::UI::Dispatch);
use BSE::Util::Tags qw(tag_hash tag_error_img);
use DevHelp::HTML qw(:default popup_menu);
use DevHelp::Validate qw(dh_validate dh_configure_fields);
use BSE::Util::Iterate;
use constant DISPLAY_TIMEOUT => 300;

my %actions =
  (
   show => 1,
   send => 1,
   done => 1,
  );

sub actions { \%actions }

sub default_action { 'show' }

my %def_rules =
  (
   from => { rules=>'email', description=>"Your email address", required=>1,
	   width=>60},
   subject => { description => "Subject", required=>1, width=>60 },
   text => { description => "Your query", required=>1,
	   htmltype=>"textarea", width=>60, height=>10 },
  );

my %form_defs =
  (
   query => 'formmail/defquery',
   done => 'formmail/defdone',
   mail => 'formmail/defemail',
   fields => 'from,subject,text',
   subject => 'User form emailed',
   require_logon => 0,
   logon_message => "You must logon for this form",
   encrypt => 0,
   crypt_class => $Constants::SHOP_CRYPTO,
   crypt_gpg => $Constants::SHOP_GPG,
   crypt_pgpe => $Constants::SHOP_PGPE,
   crypt_pgp => $Constants::SHOP_PGP,
   crypt_passphrase => $Constants::SHOP_PASSPHRASE,
   crypt_signing_id => $Constants::SHOP_SIGNING_ID,
   crypt_content_type => 0,
  );

sub _get_form {
  my ($req) = @_;

  my $cfg = $req->cfg;

  my $id = $req->cgi->param('form') || 'default';

  my $section = "$id form";

  my %form;
  $form{section} = $section;
  
  for my $field (keys(%form_defs), "email") {
    $form{$field} = $cfg->entry($section, $field, $form_defs{$field});
  }

  unless ($form{email}) {
    $form{email} = $cfg->entry('shop', 'from', $Constants::SHOP_FROM)
      or die "No email configured for form $id, and no default available\n";
  }

  my %fields;
  my @names = split /,/, $form{fields};
  for my $form_field (@names) {
    $fields{$form_field} = $def_rules{$form_field} || 
      { description => "\u$form_field" };
  }

  my $valid_section = "$id formmail validation";
  $form{validation_section} = $valid_section;
  my $fields = dh_configure_fields(\%fields, $cfg, $valid_section);
  my $extra_cfg_names = $cfg->entry($section, 'field_config', '') . ',' .
    $cfg->entry("formmail", "field_config", '');
  my %std_cfg_names = map { $_ => 1 } 
    qw(required rules description required_error range_error mindatemsg 
       maxdatemsg);
  my @extra_cfg_names = grep /\S/ && !exists $std_cfg_names{$_}, 
    split /,/, $extra_cfg_names;
  for my $name (keys %$fields) {
    my $field = $fields->{$name};
    $field->{name} = $name;

    for my $cfg_name (qw/htmltype type width height size maxlength/, 
		      @extra_cfg_names) {
      my $value = $cfg->entry($valid_section, "${name}_${cfg_name}");
      defined $value and $field->{$cfg_name} = $value;
    }
  }

  $form{validation} = $fields;
  $form{fields} = [ @$fields{@names} ];
  $form{id} = $id;

  \%form;
}

sub _get_field {
  my ($form, $rcurrent_field, $args, $acts, $templater) = @_;

  my $field;
  if ($args =~ /\S/) {
    my ($name) = DevHelp::Tags->get_parms($args, $acts, $templater);
    if ($name) {
      ($field) = $form->{validation}{$name};
      unless ($field) {
	print STDERR "Field name '$name' (from '$args') not found for values iterator\n";
	return;
      }
    }
    else {
      print STDERR "Could not extract a field name from '$args' for values iterator\n";
      return;
    }
  }
  else {
    $field = $$rcurrent_field;
    unless (defined $field) {
      print STDERR "No current field for values iterator\n";
      return;
    }
  }

  return $field;
}

sub iter_values {
  my ($form, $rcurrent_field, $args, $acts, $name, $templater) = @_;

  my $field = _get_field($form, $rcurrent_field, $args, $acts, $templater)
    or return;

  defined $field->{values} or return;

  return map +{ id => $_->[0], name => $_->[1] }, @{$field->{values}};
}

sub tag_values_select {
  my ($form, $cgi, $rcurrent_field, $args, $acts, $name, $templater) = @_;

  my $field = _get_field($form, $rcurrent_field, $args, $acts, $templater)
    or return '** Could not get field **';

  defined $field->{values} 
    or return "** field $field->{name} has no values **";

  my %labels = map @$_, @{$field->{values}};

  my ($value) = $cgi->param($field->{name});
  my @extras;
  if (defined $value) {
    push @extras, -default => $value;
  }
  
  return popup_menu(-name => $field->{name},
		    -id => $field->{name},
		    -values => [ map $_->[0], @{$field->{values}} ],
		    -labels => \%labels,
		    @extras);
}

sub tag_ifValueSet {
  my ($cgi, $rcurrent_field, $rcurrent_value) = @_;

  return 0 unless $$rcurrent_field && $$rcurrent_value;
  my @values = $cgi->param($$rcurrent_field->{name});
  return scalar(grep $_ eq $$rcurrent_value->{id}, @values);
}

sub tag_formcfg {
  my ($cfg, $form, $args, $acts, $templater) = @_;

  my ($key, $def) = DevHelp::Tags->get_parms($args, $acts, $templater);

  defined $def or $def = '';
  defined $key or return '** key argument missing from formcfg tag **';

  escape_html($cfg->entry($form->{section}, $key, $def));
}

sub req_show {
  my ($class, $req, $errors) = @_;

  my $form = _get_form($req);

  if ($form->{require_logon}) {
    $req->siteuser
      or return _refresh_logon($req, $form);
  }

  my $msg = $req->message($errors);

  my $it = BSE::Util::Iterate->new;
  my %acts;
  my $current_field;
  my $current_value;
  %acts =
    (
     BSE::Util::Tags->basic(\%acts, $req->cgi, $req->cfg),
     error_img => [ \&tag_error_img, $req->cfg, $errors ],
     $it->make_iterator(undef, 'field', 'fields', $form->{fields},
			undef, undef, \$current_field),
     msg => $msg,
     id => $form->{id},
     $it->make_iterator([ \&iter_values, $form, \$current_field ],
			'value', 'values', undef, undef,
			'nocache', \$current_value),
     values_select => 
     [ \&tag_values_select, $form, $req->cgi, \$current_field ],
     ifValueSet => 
     [ \&tag_ifValueSet, $req->cgi, \$current_field, \$current_value ],
     formcfg => [ \&tag_formcfg, $req->cfg, $form ],
    );

  return $req->response($form->{query}, \%acts);
}

sub iter_cgi_values {
  my ($form, $rcurrent_field, $args, $acts, $name, $templater) = @_;

  my $field = _get_field($form, $rcurrent_field, $args, $acts, $templater)
    or return;
  
  $field->{value_array} or return;

  $field->{values} or
    return map +{ id => $_, name => $_ }, @{$field->{value_array}};

  my %poss_values = map { $_->[0] => $_->[1] } @{$field->{values}};

  return map +{ id => $_, name => $poss_values{$_} }, @{$field->{value_array}};
}

sub req_send {
  my ($class, $req) = @_;

  my $form = _get_form($req);

  if ($form->{require_logon}) {
    $req->siteuser
      or return _refresh_logon($req, $form);
  }

  my $cgi = $req->cgi;
  my $cfg = $req->cfg;

  my %form = ( fields =>$form->{validation}, rules=>{} );

  my %errors;
  dh_validate($cgi, \%errors, \%form, $cfg, $form->{validation_section});

  keys %errors
    and return $class->req_show($req, \%errors);

  # grab our values
  my %values;
  my %array_values;
  for my $field (@{$form->{fields}}) {
    my $name = $field->{name};
    my @values = $cgi->param($name);
    $field->{value} = $values{$name} = "@values";
    $field->{value_array} = $array_values{$name} = \@values;
  }

  # send an email
  my $user = $req->siteuser;
  my $it = BSE::Util::Iterate->new;
  my %acts;
  my $current_field;
  %acts =
    (
     BSE::Util::Tags->static(\%acts, $cfg),
     ifUser=>!!$user,
     user => $user ? [ \&tag_hash, $user ] : '',
     value => [ \&tag_hash, \%values ],
     $it->make_iterator(undef, 'field', 'fields', $form->{fields}, 
			undef, undef, \$current_field),
     $it->make_iterator([ \&iter_cgi_values, $form, \$current_field ],
			'value', 'values', undef, undef, 'nocache'),
     id => $form->{id},
     formcfg => [ \&tag_formcfg, $req->cfg, $form ],
     remote_addr => escape_html($ENV{REMOTE_ADDR}),
    );

  require BSE::Mail;
  my $mailer = BSE::Mail->new(cfg=>$cfg);
  my $content = BSE::Template->get_page($form->{mail}, $cfg, \%acts);
  my @headers;
  if ($form->{encrypt}) {
    $content = $class->_encrypt($cfg, $form, $content);
    push @headers, "Content-Type: application/pgp; format=text; x-action=encrypt\n"
      if $form->{crypt_content_type};
  }
  unless ($mailer->send(to=>$form->{email}, from=>$form->{email},
			subject=>$form->{subject}, body=>$content,
			headers => join('', @headers))) {
    print STDERR "Error sending mail: ", $mailer->errstr, "\n";
    $errors{_mail} = $mailer->{errstr};
    return $class->req_show($req, \%errors);
  }

  # make them available to the a_sent handler
  my $session = $req->session;
  $session->{formmail} = \%values;
  $session->{formmail_array} = \%array_values;
  $session->{formmail_done} = time;

  my $url = $ENV{SCRIPT} . "?a_done=1&form=$form->{id}&t=".$session->{formmail_done};

  return BSE::Template->get_refresh($url, $cfg);
}

sub req_done {
  my ($class, $req) = @_;

  my $form = _get_form($req);

  my $session = $req->session;
  $session->{formmail} && $session->{formmail_done}
    or return $class->req_show($req);
    
  my $time = $req->cgi->param('t');
  $time == $session->{formmail_done}
    or return $class->req_show($req);

  my $now = time;
  $now <= $time + DISPLAY_TIMEOUT
    or return $class->req_show($req);

  my $values = $session->{formmail};
  for my $field (@{$form->{fields}}) {
    $field->{value} = $values->{$field->{name}};
  }
  my $it = BSE::Util::Iterate->new;
  my %acts;
  %acts =
    (
     BSE::Util::Tags->basic(\%acts, $req->cgi, $req->cfg),
     $it->make_iterator(undef, 'field', 'fields', $form->{fields}),
     id => $form->{id},
     value => [ \&tag_hash, $values ],
     formcfg => [ \&tag_formcfg, $req->cfg, $form ],
    );

  return $req->response($form->{done}, \%acts);
}

sub _encrypt {
  my ($class, $cfg, $form, $content) = @_;

  (my $class_file = $form->{crypt_class}.".pm") =~ s!::!/!g;
  require $class_file;
  my $encryptor = $form->{crypt_class}->new;
  my %opts =
    (
     passphrase => $form->{crypt_passphrase},
     stripwarn => 1,
     debug => $cfg->entry('debug', 'mail_encryption', 0),
     sign => !!$form->{crypt_signing_id},
     secretkeyid => $form->{crypt_signing_id},
     pgp => $form->{crypt_pgp},
     pgpe => $form->{crypt_pgpe},
     gpg => $form->{crypt_gpg},
    );

  my $result = $encryptor->encrypt($form->{email}, $content, %opts)
    or die "Cannot encrypt ",$encryptor->error;

  $result;
}

sub _refresh_logon {
  my ($req, $form) = @_;

  my $r = $ENV{SCRIPT_NAME}."?form=".$form->{id};
  my $logon = "/cgi-bin/user.pl?show_logon=1&r=".escape_uri($r)
    ."&message=".escape_uri($form->{logon_message});
  return BSE::Template->get_refresh($logon, $req->cfg);
}

1;
