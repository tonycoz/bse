package BSE::UI::Formmail;
use strict;
use base qw(BSE::UI::Dispatch);
use BSE::Util::Tags qw(tag_hash tag_error_img);
use DevHelp::HTML;
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
  );


sub _get_form {
  my ($req) = @_;

  my $cfg = $req->cfg;

  my $id = $req->cgi->param('form') || 'default';

  my $section = "$id form";

  my %form;
  
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

  my $fields = dh_configure_fields(\%fields, $cfg, "$id formmail validation");
  $fields->{$_}{name} = $_ for keys %$fields;

  $form{validation} = $fields;
  $form{fields} = [ @$fields{@names} ];
  $form{id} = $id;

  \%form;
}

sub req_show {
  my ($class, $req, $errors) = @_;

  my $form = _get_form($req);

  my $msg = $req->message($errors);

  my $it = BSE::Util::Iterate->new;
  my %acts;
  %acts =
    (
     BSE::Util::Tags->basic(\%acts, $req->cgi, $req->cfg),
     error_img => [ \&tag_error_img, $req->cfg, $errors ],
     $it->make_iterator(undef, 'field', 'fields', $form->{fields}),
     msg => $msg,
     id => $form->{id},
    );

  return $req->response($form->{query}, \%acts);
}

sub req_send {
  my ($class, $req) = @_;

  my $form = _get_form($req);

  my $cgi = $req->cgi;
  my $cfg = $req->cfg;

  my %form = ( fields =>$form->{validation}, rules=>{} );

  my %errors;
  dh_validate($cgi, \%errors, \%form); # already configured

  keys %errors
    and return $class->req_show($req, \%errors);

  # grab our values
  my %values;
  for my $field (@{$form->{fields}}) {
    $field->{value} = $values{$field->{name}} = 
      join '', $cgi->param($field->{name});
  }

  # send an email
  my $user = $req->siteuser;
  my $it = BSE::Util::Iterate->new;
  my %acts;
  %acts =
    (
     BSE::Util::Tags->static(\%acts, $cfg),
     ifUser=>!!$user,
     user => $user ? [ \&tag_hash, $user ] : '',
     value => [ \&tag_hash, \%values ],
     $it->make_iterator(undef, 'field', 'fields', $form->{fields}),
     id => $form->{id},
    );

  require BSE::Mail;
  my $mailer = BSE::Mail->new(cfg=>$cfg);
  my $content = BSE::Template->get_page($form->{mail}, $cfg, \%acts);
  unless ($mailer->send(to=>$form->{email}, from=>$form->{email},
			subject=>$form->{subject}, body=>$content)) {
    print STDERR "Error sending mail: ", $mailer->errstr, "\n";
    $errors{_mail} = $mailer->{errstr};
    return $class->req_show($req, \%errors);
  }

  # make them available to the a_sent handler
  my $session = $req->session;
  $session->{formmail} = \%values;
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
    );

  return $req->response($form->{done}, \%acts);
}

1;
