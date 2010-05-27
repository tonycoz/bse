package BSE::UI::AdminMessages;
use strict;
use base 'BSE::UI::AdminDispatch';
use BSE::Util::Iterate;
use BSE::Message;

my %actions =
  (
   index => "bse_msg_view",
   catalog => "bse_msg_view",
   detail => "bse_msg_view",
   save => "bse_msg_save",
   delete => "bse_msg_delete",
  );

sub actions { \%actions }

sub rights { \%actions }

sub default_action { "index" }

sub req_index {
  my ($self, $req) = @_;

  my %acts =
    (
     $req->admin_tags,
    );

  return $req->dyn_response("admin/msgs/index", \%acts);
}

sub req_catalog {
  my ($self, $req) = @_;

  return $req->json_content
    (
     success => 1,
     messages => [ BSE::DB->query("bseAllMsgs") ],
    );
}

sub req_detail {
  my ($self, $req) = @_;

  my $id = $req->cgi->param("id");
  my %errors;
  unless ($id) {
    $errors{id} = "msg:bse/admin/message/noid";
  }
  unless ($errors{id}) {
    $id =~ m(^[a-z]\w*(/\w+)+$)
      or $errors{id} = "msg:bse/admin/message/invalidid";
  }
  keys %errors
    and return $self->_field_error($req, \%errors);

  my ($base) = BSE::DB->query(bseMessageDetail => $id);
  my (@defaults) = BSE::DB->query(bseMessageDefaults => $id);
  # we only want the highest priority defaults
  my %real_defs;
  for my $def (@defaults) {
    if (!$real_defs{$def->{language_code}}
	|| $real_defs{$def->{language_code}}{priority} < $def->{priority}) {
      $real_defs{$def->{language_code}} = $def;
    }
  }
  my @real_defs = sort { $a->{language_code} cmp $b->{language_code} } values %real_defs;
  my (@defns) = BSE::DB->query(bseMessageDefinitions => $id);
  my @langs = BSE::Message->languages;

  return $req->json_content
    (
     success => 1,
     base => $base,
     languages => \@langs,
     defaults => { map { $_->{language_code} => $_ } @real_defs },
     definitions => { map { $_->{language_code} => $_ } @defns },
    );
}

my %msg_rules =
  (
   bse_msg_id =>
   {
    match => qr(^(?:x-)?[a-z]\w*(?:/\w+)+$),
    error => "msg:bse/admin/message/invalidid",
   },
   bse_msg_language =>
   {
    match => qr/^[a-z_-]+$/i,
    error => "msg:bse/admin/message/invalidlang",
   },
  );

my %save_fields =
  (
   id =>
   {
    description => "Message ID",
    rules => "required;bse_msg_id",
   },
   language_code =>
   {
    description => "Language Code",
    rules => "required;bse_msg_language",
   },
   message =>
   {
    description => "Message text",
    rules => "required",
   },
  );

sub req_save {
  my ($self, $req) = @_;

  my $cgi = $req->cgi;
  my $id = $cgi->param("id");
  my $lang = $cgi->param("language_code");
  my $text = $cgi->param("message");
  my %errors;
  $req->validate(fields => \%save_fields,
		 rules => \%msg_rules,
		 errors => \%errors);

  my $base;
  unless ($errors{id}) {
    ($base) = BSE::DB->query(bseMessageDetail => $id);
    $base
      or $errors{id} = "msg:bse/admin/message/unknownid";
  }
  unless ($errors{language_code}) {
    my @langs = BSE::Message->languages;
    grep $lang eq $_->{id}, @langs
      or $errors{language_code} = "msg:bse/admin/message/unknownlang";
  }
  if ($base && !$base->{multiline}) {
    $text =~ /\n/
      and $errors{message} = "msg:bse/admin/message/badmultiline:$id";
  }
  keys %errors
    and return $self->_field_error($req, \%errors);

  if (my ($row) = BSE::DB->query(bseMessageFetch => $id, $lang)) {
    BSE::DB->run(bseMessageUpdate => $text, $id, $lang);
  }
  else {
    BSE::DB->run(bseMessageCreate => $id, $lang, $text);
  }

  BSE::Message->uncache($id);

  return $req->json_content
    (
     success => 1,
     definition =>
     {
      id => $id,
      language_code => $lang,
      message => $text,
     },
    );
}

my %delete_fields =
  (
   id =>
   {
    description => "Message ID",
    rules => "required;bse_msg_id",
   },
   language_code =>
   {
    description => "Language Code",
    rules => "required;bse_msg_language",
   },
  );

sub req_delete {
  my ($self, $req) = @_;

  my $cgi = $req->cgi;
  my $id = $cgi->param("id");
  my $lang = $cgi->param("language_code");

  my %errors;
  $req->validate(fields => \%delete_fields,
		 rules => \%msg_rules,
		 errors => \%errors);

  my $base;
  unless ($errors{id}) {
    ($base) = BSE::DB->query(bseMessageDetail => $id);
    $base
      or $errors{id} = "msg:bse/admin/message/unknownid";
  }
  unless ($errors{language_code}) {
    my @langs = BSE::Message->languages;
    grep $lang eq $_->{id}, @langs
      or $errors{language_code} = "msg:bse/admin/message/unknownlang";
  }
  keys %errors
    and return $self->_field_error($req, \%errors);

  BSE::DB->run(bseMessageDelete => $id, $lang);

  BSE::Message->uncache($id);

  return $req->json_content
    (
     success => 1,
    );
}

1;
