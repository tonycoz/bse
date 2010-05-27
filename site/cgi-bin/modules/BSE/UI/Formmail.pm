package BSE::UI::Formmail;
use strict;
use base qw(BSE::UI::Dispatch);
use BSE::Util::Tags qw(tag_hash tag_hash_plain tag_error_img);
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
#   crypt_class => $Constants::SHOP_CRYPTO,
#   crypt_gpg => $Constants::SHOP_GPG,
#   crypt_pgpe => $Constants::SHOP_PGPE,
#   crypt_pgp => $Constants::SHOP_PGP,
   crypt_passphrase => $Constants::SHOP_PASSPHRASE,
   crypt_signing_id => $Constants::SHOP_SIGNING_ID,
#   crypt_content_type => 0,
   autofill => 1,
   title => 'Send us a comment',
   send_email => 1,
   sql=>'',
   sql_params => undef,
   sql_dsn => undef,
   sql_options => '',
   sql_user => undef,
   sql_password => undef,
   spam_check_field => undef,
   log_spam_check_fail => 1,
   email_select => undef,
   recaptcha => 0,
  );

sub _get_form {
  my ($req) = @_;

  my $cfg = $req->cfg;

  my $id = $req->cgi->param('form');
  defined $id and $id =~ /\A[A-Za-z0-9_-]+\z/
    or $id = 'default';

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

  my $has_file_fields = 0;

  my $valid_section = "$id formmail validation";
  $form{validation_section} = $valid_section;
  my $fields = dh_configure_fields(\%fields, $cfg, $valid_section, BSE::DB->single->dbh);
  my $extra_cfg_names = $cfg->entry($section, 'field_config', '') . ',' .
    $cfg->entry("formmail", "field_config", '');
  my %std_cfg_names = map { $_ => 1 } 
    qw(required rules description required_error range_error mindatemsg 
       maxdatemsg default maxfilesize filetoobigmsg);
  my @extra_cfg_names = grep /\S/ && !exists $std_cfg_names{$_}, 
    split /,/, $extra_cfg_names;
  my $user = $req->siteuser;
  for my $name (keys %$fields) {
    my $field = $fields->{$name};
    $field->{name} = $name;

    for my $cfg_name (qw/htmltype type width height size maxlength default
                         maxfilesize filetoobigmsg/, @extra_cfg_names) {
      my $value = $cfg->entry($valid_section, "${name}_${cfg_name}");
      defined $value and $field->{$cfg_name} = $value;
    }

    if ($form{autofill} && $user && exists $user->{$name}) {
      $field->{default} = $user->{$name};
    }
    
    if ($field->{htmltype} && $field->{htmltype} eq 'file') {
      $has_file_fields = 1;
      $field->{filetoobigmsg} ||= 'File %s too large';
    }
  }

  $form{validation} = $fields;
  $form{fields} = [ @$fields{@names} ];
  $form{id} = $id;
  $form{has_file_fields} = $has_file_fields;

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
  defined $value or $value = $field->{default};
  my @extras;
  if (defined $value) {
    push @extras, -default => $value;
  }
  if ($field->{value_groups}) {
    push @extras, -groups => $field->{value_groups};
  }
  
  return popup_menu(-name => $field->{name},
		    -id => $field->{name},
		    -values => [ map $_->[0], @{$field->{values}} ],
		    -labels => \%labels,
		    @extras);
}

sub tag_ifValueSet {
  my ($cgi, $rcurrent_field, $rcurrent_value, $errors) = @_;

  return 0 unless $$rcurrent_field && $$rcurrent_value;
  my @values = $cgi->param($$rcurrent_field->{name});
  if (!$errors and !@values and defined $$rcurrent_field->{default}) {
    @values = split /;/, $$rcurrent_field->{default};
  }
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
     $req->dyn_user_tags(),
     error_img => [ \&tag_error_img, $req->cfg, $errors ],
     $it->make_iterator(undef, 'field', 'fields', $form->{fields},
			undef, undef, \$current_field),
     msg => $msg,
     id => escape_html($form->{id}),
     $it->make_iterator([ \&iter_values, $form, \$current_field ],
			'value', 'values', undef, undef,
			'nocache', \$current_value),
     values_select => 
     [ \&tag_values_select, $form, $req->cgi, \$current_field ],
     ifValueSet => 
     [ \&tag_ifValueSet, $req->cgi, \$current_field, \$current_value, $errors ],
     formcfg => [ \&tag_formcfg, $req->cfg, $form ],
     ifFormHasFileFields => $form->{has_file_fields},
     ifRecaptcha => $form->{recaptcha},
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

sub _send_to_db {
  my ($form, $user, $errors) = @_;

  if ($form->{has_file_fields}) {
    $errors->{_database} = "Forms with file fields cannot be saved to the database";
    return;
  }

  my $dbh;
  my $conn_dbh;
  
  if ($form->{sql_dsn}) {
    my %options = split /[,=]/, $form->{sql_options};
    if ($conn_dbh = DBI->connect($form->{sql_dsn}, $form->{sql_user},
				 $form->{sql_password}, \%options)) {
      $dbh = $conn_dbh;
    }
    else {
      print STDERR "Error connecting to the database for $form->{id}: ", DBI->errstr,"\n";
      $errors->{_database} =
	"Error connecting to the database.  Please contact the webmaster.";
      return;
    }
  }
  else {
    $dbh = BSE::DB->single->dbh;
  }

  my @params;
  if ($form->{sql_params}) {
    my %names = map { $form->{fields}[$_]{name} => $_ } 0 .. $#{$form->{fields}};
    for my $param (split /,/, $form->{sql_params}) {
      if ($param =~ /^\{(\w+)\}$/) {
	if ($user && defined $user->{$1}) {
	  push @params, $user->{$1};
	}
	else {
	  push @params, '';
	}
      }
      elsif ($param =~ /^env\{(\w+)\}$/) {
	my $key = $1;
	if (defined $ENV{$key}) {
	  push @params, $ENV{$key};
	}
	else {
	  push @params, '';
	}
      }
      else {
	if (exists $names{$param}
	    && defined $form->{fields}[$names{$param}]{value}) {
	  push @params, $form->{fields}[$names{$param}]{value};
	}
	else {
	  print STDERR "Unknown sql_param field $param\n";
	  push @params, '';
	}
      }
    }
  }
  else {
    # assume they want everything
    @params = map $_->{value}, @{$form->{fields}};
  }

  my $sth = $dbh->prepare($form->{sql});
  unless ($sth) {
    print STDERR "Cannot prepare $form->{id} SQL: ",$dbh->errstr,"\n";
    $conn_dbh->disconnect if $conn_dbh;
    $errors->{_database} =
      "Error preparing SQL for execution.  Please contact the webmaster.";
    return;
  }
  
  unless ($sth->execute(@params)) {
    print STDERR "Cannot execute $form->{id} SQL: ", $dbh->errstr,"\n";
    for my $index (0..$#params) {
      print STDERR " $index: $params[$index]\n";
    }
    $errors->{_database} =
      "Error executing SQL.  Please contact the webmaster.";
    return;
  }
  $sth->finish; # just in case
  undef $sth;
  $conn_dbh->disconnect if $conn_dbh;

  return 1;
}

sub tag_formcfg_plain {
  my ($cfg, $form, $args, $acts, $templater) = @_;

  my ($key, $def) = DevHelp::Tags->get_parms($args, $acts, $templater);

  defined $def or $def = '';
  defined $key or return '** key argument missing from formcfg tag **';

  $cfg->entry($form->{section}, $key, $def);
}

sub _send_to_mail {
  my ($class, $form, $user, $values, $errors, $req) = @_;

  my $cfg = $req->cfg;

  # send an email
  my $it = DevHelp::Tags::Iterate->new;
  my %acts;
  my $current_field;
  %acts =
    (
     BSE::Util::Tags->static(\%acts, $cfg),
     ifUser=>!!$user,
     user => $user ? [ \&tag_hash_plain, $user ] : '',
     value => [ \&tag_hash_plain, $values ],
     $it->make_iterator(undef, 'field', 'fields', $form->{fields}, 
			undef, undef, \$current_field),
     $it->make_iterator([ \&iter_cgi_values, $form, \$current_field ],
			'value', 'values', undef, undef, 'nocache'),
     id => $form->{id},
     formcfg => [ \&tag_formcfg_plain, $req->cfg, $form ],
     remote_addr => $ENV{REMOTE_ADDR},
    );

  my $to_email = $form->{email};
  if ($form->{email_select}
      && $form->{email_select} =~ /^(\w+);(.+)$/) {
    my ($field_name, $section) = ( $1, $2 );
    my ($field) = grep $_->{name} eq $field_name, @{$form->{fields}};
    if ($field && $cfg->entry($section, $field->{value})) {
      $to_email = $cfg->entry($section, $field->{value});
    }
  }
  
  require BSE::ComposeMail;
  my $mailer = BSE::ComposeMail->new(cfg=>$cfg);
  $mailer->start(to => $to_email,
		 from => $form->{email},
		 subject=>$form->{subject},
		 template => $form->{mail},
		 acts => \%acts);
  if ($form->{encrypt}) {
    $mailer->encrypt_body(passphrase => $form->{crypt_passphrase},
			  signing_id => $form->{crypt_signing_id});
  }
  if ($form->{has_file_fields}) {
    my $seq = 1;
    for my $field (grep $_->{htmltype} && $_->{htmltype} eq 'file'
		   && $_->{value}, @{$form->{fields}}) {
      my $display = $field->{value};
      $display =~ s!.*[/\\:]!!;
      $display ||= 'unknown_' . $seq++;
      my $type = $field->{type} || 'application/octet-stream';

      my $url = $mailer->attach(disposition => 'attachment',
			      display => $display,
			      type => $type,
			      fh => $field->{fh});
      unless ($url) {
	$errors->{_mail} = $mailer->errstr;
	return;
      }
      $field->{url} = $url;
    }
  }
  unless ($mailer->done()) {
    print STDERR "Error sending mail: ", $mailer->errstr, "\n";
    $errors->{_mail} = $mailer->errstr;
    return;
  }

  return 1;
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

  my %form =
    ( 
     fields => $form->{validation},
     rules=>{},
     dbh => BSE::DB->single->dbh,
    );

  my %errors;
  dh_validate($cgi, \%errors, \%form, $cfg, $form->{validation_section});

  if ($form->{has_file_fields}) {
    # validate the file sizes
    for my $field (grep $_->{htmltype} && $_->{htmltype} eq 'file', 
		   @{$form->{fields}}) {
      my $name = $field->{name};
      # presumably required is being handled by the validation above
      my $filename = $cgi->param($name);
      my $fh = $cgi->upload($name);
      if ($filename && $fh) {
	if ($field->{maxfilesize} && -s $fh > $field->{maxfilesize}) {
	  ($errors{$name} = $field->{filetoobigmsg})
	    =~ s/%s/$field->{description}/;
	}
	$field->{fh} = $fh;
	$field->{type} = $cgi->uploadInfo($filename)->{'Content-Type'};
      }
    }
  }

  if ($form->{recaptcha}) {
    my $error;
    unless ($req->test_recaptcha(error => \$error)) {
      $errors{recaptcha} = $error;
    }
  }

  keys %errors
    and return $class->req_show($req, \%errors);

  # grab our values
  my %values;
  my %array_values;
  for my $field (@{$form->{fields}}) {
    my $name = $field->{name};
    # prevent GLOBs in the values, since these end up in the session
    my @values = map $_.'', $cgi->param($name);
    $field->{value} = $values{$name} = "@values";
    $field->{value_array} = $array_values{$name} = \@values;
  }

  # spammer check field
  my $do_send = 1;
  if ($form->{spam_check_field}) {
    my $value = $cgi->param($form->{spam_check_field});
    if (!defined $value || $value ne '') {
      if ($form->{log_spam_check_fail}) {
	print STDERR "Possible spam fmail request from $ENV{REMOTE_ADDR}\n";
      }
      $do_send = 0;
    }
  }

  if ($do_send) {
    my $user = $req->siteuser;
    if ($form->{sql}) {
      _send_to_db($form, $user, \%errors)
	or return $class->req_show($req, \%errors);
    }
    
    if ($form->{send_email}) {
      $class->_send_to_mail($form, $user, \%values, \%errors, $req)
	or $class->req_show($req, \%errors);
    }
  }

  my $url = $cgi->param('r');
  if (!$url) {
    # make them available to the a_sent handler
    my $session = $req->session;
    $session->{formmail} = \%values;
    $session->{formmail_array} = \%array_values;
    $session->{formmail_done} = time;
    
    $url = $ENV{SCRIPT_NAME} . "?a_done=1&form=$form->{id}&t=".$session->{formmail_done};
  }
    
  return BSE::Template->get_refresh($url, $cfg);
}

sub iter_done_values {
  my ($form, $rcurrent_field, $req, $args, $acts, $name, $templater) = @_;

  my $field = _get_field($form, $rcurrent_field, $args, $acts, $templater)
    or return;
  
  my $array_values = $req->session->{formmail_array}
    or return;

  $field->{values}
    or return map +{ id => $_, name => $_ }, @{$array_values->{$field->{name}}};

  my %poss_values = map { $_->[0] => $_->[1] } @{$field->{values}};

  return map +{ id => $_, name => $poss_values{$_} },
    @{$array_values->{$field->{name}}};
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
  my $current_field;
  my %acts;
  %acts =
    (
     $req->dyn_user_tags(),
     $it->make_iterator(undef, 'field', 'fields', $form->{fields},
		       undef, undef, \$current_field),
     $it->make_iterator([ \&iter_done_values, $form, \$current_field, $req ],
			'value', 'values', undef, undef, 'nocache'),
     id => $form->{id},
     formcfg => [ \&tag_formcfg, $req->cfg, $form ],
    );

  return $req->response($form->{done}, \%acts);
}

sub _refresh_logon {
  my ($req, $form) = @_;

  my $r = $ENV{SCRIPT_NAME}."?form=".$form->{id};
  my $logon = "/cgi-bin/user.pl?show_logon=1&r=".escape_uri($r)
    ."&message=".escape_uri($form->{logon_message});
  return BSE::Template->get_refresh($logon, $req->cfg);
}

1;
