package BSE::UI::SiteUserUpdate;
use strict;
use base qw(BSE::UI::AdminDispatch);
use BSE::Template;
use SiteUsers;
use BSE::Util::Iterate;
use BSE::Util::Tags qw(tag_error_img);
use DevHelp::HTML;
use DevHelp::Validate;
use BSE::Util::Secure qw/make_secret/;
use BSE::SubscribedUsers;
use BSE::CfgInfo qw(custom_class);

my %rights =
  (
   importform => 'bse_siteuser_list',
   preview => 'bse_siteuser_list',
   import => 'bse_siteuser_edit',
  );

my %cant_update = map { $_ => 1 }
  qw/whenRegistered lastLogon confirmed confirmSecret waitingForConfirmation/;

sub actions { \%rights }

sub rights { \%rights }

sub default_action { 'importform' }

sub _get_import_spec {
  my ($req, $name, $error) = @_;

  my $cfg = $req->cfg;

  my %spec = ( name => $name );

  my $section = "siteuser update $name";
  $spec{description} = $cfg->entry("siteuser updates", $name);
  my @fields = split /;/, $cfg->entry($section, 'fields', '');
  unless (@fields) {
    $$error = "No fields for siteuser update spec $name\n";
    return;
  }
  my $gotkey;
  for my $field (@fields) {
    if ($field eq 'id' || $field eq 'userId') {
      if ($gotkey) {
	# only one key allowed
	$$error = "Fields list may only contain one of id, userId\n";
	return;
      }
      $spec{key} = $field;
      ++$gotkey;
    }
    if ($cant_update{$field}) {
      $$error = "Field $field can't be updated";
      return;
    }
  }
  unless ($gotkey) {
    $$error = "Fields list must contain id or userId\n";
    return;
  }
  my %valid_fields = map { $_ => 1 } SiteUser->columns;
  unless (@fields == grep($valid_fields{$_} || $_ eq "x", @fields)) {
    $$error = "Unknown fields in field list for $name\n";
    return;
  }
  $spec{fields} = \@fields;
  $spec{section} = $section;

  \%spec;
}

sub _get_import_list {
  my ($req) = @_;

  my %entries = $req->cfg->entries("siteuser updates");
  my @specs;
  for my $key (keys %entries) {
    my $error;
    my $spec = _get_import_spec($req, $key, \$error);
    if ($spec) {
      push @specs, $spec;
    }
    else {
      $req->flash("Cannot load spec $key: $error");
    }
  }

  @specs;
}

sub req_importform {
  my ($class, $req, $errors) = @_;

  my @specs = sort { lc $a->{description} cmp lc $b->{description} }
    _get_import_list($req);

  my $msg = $req->message($errors);

  my $it = BSE::Util::Iterate->new;
  my %acts;
  %acts =
    (
     BSE::Util::Tags->basic(\%acts, $req->cgi, $req->cfg),
     BSE::Util::Tags->admin(\%acts, $req->cfg),
     BSE::Util::Tags->secure($req),
     error_img => [ \&tag_error_img, $req->cfg, $errors ],
     $it->make_iterator(undef, 'importspec', 'importspecs', \@specs),
     message => $msg,
    );

  return $req->dyn_response('admin/memberupdate/request', \%acts);
}

sub tag_line {
  my ($curline, $arg, $acts, $name, $templater) = @_;

  my ($field) = DevHelp::Tags->get_parms($arg, $acts, $templater)
    or return '** missing field name **';

  my $value = $$curline->{$field};
  defined $value or $value = '';

  escape_html($value);
}

sub req_preview {
  my ($class, $req) = @_;

  my $cgi = $req->cgi;
  my $cfg = $req->cfg;
  my %errors;
  my $filename = $cgi->param('file');
  my $fh;
  if ($filename) {
    $fh = $cgi->upload('file');
    unless ($fh) {
      $errors{file} = "file needs to be a file field and the form needs to have enctype set to multipart/form-data";
    }
  }
  else {
    $errors{file} = "Please enter a filename";
  }

  my $specname = $cgi->param('importspec');
  my $spec;
  if (defined $specname and length $specname) {
    my $error;
    $spec = _get_import_spec($req, $specname, \$error)
      or $errors{importspec} = "Unknown or invalid import specification: $error";
  }
  else {
    $errors{importspec} = "Please select an import specification";
  }

  keys %errors
    and return $class->req_importform($req, \%errors);

  my @log;
  my @data = _parse($fh, $spec, \%errors, \@log, $cfg);

  my %line_errors;
  my $line_error_count = 0;
  for my $row_num (0..$#data) {
    my $row = $data[$row_num];
    if ($row->{errors}) {
      $line_errors{$_}[$row_num] = $row->{errors}{$_}
	for keys %{$row->{errors}};
      ++$line_error_count,
    }
  }

  my @real_fields = grep $_ ne "x", @{$spec->{fields}};
  my @iter_fields = 
    map 
      +{ 
	name => $_,
	description => $cfg->entry($spec->{section}, "${_}_description", $_)
       }, @real_fields;
  my $it = BSE::Util::Iterate->new;
  my %acts;
  my $curline;
  %acts =
    (
     BSE::Util::Tags->basic(\%acts, $cgi, $cfg),
     BSE::Util::Tags->admin(\%acts, $cfg),
     BSE::Util::Tags->secure($req),
     line_error => [ \&tag_error_img, $cfg, \%line_errors ],
     $it->make_iterator(undef, 'line', 'lines', \@data, undef, undef, \$curline),
     line_error_count => $line_error_count,
     line_good_count => @data - $line_error_count,
     line => [ \&tag_line, \$curline ],
     $it->make_iterator(undef, 'field', 'fields', \@iter_fields),
    );

  return $req->dyn_response('admin/memberupdate/preview', \%acts);
}

sub req_import {
  # if the email changes reset the confirmation status, if the user has
  # any subs we'll need to email a new confirmation message
  my ($class, $req) = @_;


  my $cgi = $req->cgi;
  my $cfg = $req->cfg;

  my $custom = custom_class($cfg);

  my %errors;
  my $filename = $cgi->param('file');
  my $fh;
  if ($filename) {
    $fh = $cgi->upload('file');
    unless ($fh) {
      $errors{file} = "file needs to be a file field and the form needs to have enctype set to multipart/form-data";
    }
  }
  else {
    $errors{file} = "Please enter a filename";
  }

  my $specname = $cgi->param('importspec');
  my $spec;
  if (defined $specname and length $specname) {
    my $error;
    $spec = _get_import_spec($req, $specname, \$error)
      or $errors{importspec} = "Unknown or invalid import specification: $error";
  }
  else {
    $errors{importspec} = "Please select an import specification";
  }

  keys %errors
    and return $class->req_importform($req, \%errors);

  my @log;
  my @data = _parse($fh, $spec, \%errors, \@log, $cfg);

  my %line_errors;
  my $line_error_count = 0;
  for my $row_num (0..$#data) {
    my $row = $data[$row_num];
    if ($row->{errors}) {
      $line_errors{$_}[$row_num] = $row->{errors}{$_}
	for keys %{$row->{errors}};
      ++$line_error_count,
    }
  }

  my $nopassword = $cfg->entryBool('site users', 'nopassword', 0);

  my @fields = @{$spec->{fields}};
  my $have_email = grep($_ eq 'email', @fields);
  for my $row (grep !$_->{errors}, @data) {
    my $user;
    if ($spec->{key} eq 'id') {
      $user = SiteUsers->getByPkey($row->{id});
    }
    else {
      $user = SiteUsers->getBy(userId => $row->{userId});
    }
    unless ($user) {
      $row->{errors}{$spec->{key}} = "Could not load user";
      next;
    }

    my $new_email = $have_email && $row->{email} ne $user->{email};
    # store them
    for my $field (keys %$row) {
      $user->set($field => $row->{$field});
    }

    if ($new_email) {
      $user->{confirmed} = 0;
      $user->{confirmSecret} = make_secret($cfg);
      my $msg;
      if ($nopassword) {
	my $code;
	my $sent_ok = $user->send_conf_request($cgi, $cfg, \$code, \$msg);
      }
      else {
	if (BSE::SubscribedUsers->getBy(userId => $user->{id})) {
	  # send a new confirmation email
	  my $code;
	  my $sent_ok = $user->send_conf_request($cgi, $cfg, \$code, \$msg);
	}
      }
    }
    $user->save;
    $custom->can('siteuser_edit')
      and $custom->siteuser_edit($user, 'import', $cfg);
  }

  my @iter_fields = 
    map 
      +{ 
	name => $_,
	description => $cfg->entry($spec->{section}, "${_}_description", $_)
       }, @{$spec->{fields}};
  my $it = BSE::Util::Iterate->new;
  my %acts;
  my $curline;
  %acts =
    (
     BSE::Util::Tags->basic(\%acts, $cgi, $cfg),
     BSE::Util::Tags->admin(\%acts, $cfg),
     BSE::Util::Tags->secure($req),
     line_error => [ \&tag_error_img, $cfg, \%line_errors ],
     $it->make_iterator(undef, 'line', 'lines', \@data, undef, undef, \$curline),
     line_error_count => $line_error_count,
     line_good_count => @data - $line_error_count,
     line => [ \&tag_line, \$curline ],
     $it->make_iterator(undef, 'field', 'fields', \@iter_fields),
    );

  return $req->dyn_response('admin/memberupdate/import', \%acts);
}

sub _parse {
  my ($fh, $spec, $errors, $log, $cfg) = @_;

  my $data;
  {
    local $/;
    $data = <$fh>;
  };
  my @lines;
  if ($data =~ /\cJ/) {
    $data =~ tr/\cM//d;
    @lines = split /\cJ/, $data;
    push @$log, "PC or Unix text file";
  }
  elsif ($data =~ /\cM/) { # someone gave us a Mac file
    @lines = split /\cM/, $data;
    push @$log, "Macintosh text file\n";
  }
  else {
    $errors->{filename} = "The file is empty or contains no line separators";
    return;
  }
  my $sep;
  if ($lines[0] =~ /\t/) {
    $sep = "\t";
    push @$log, "Using TAB as a field separator";
  }
  else {
    $sep = ",";
    push @$log, "Using comma as a field separator";
  }

  my %valid;
  my @fields = @{$spec->{fields}};
  my $key = $spec->{key};
  if ($key eq 'id') {
    $valid{id} = { required => 1, rules => 'positiveint', description => 'id' };
  }
  else {
    $valid{userId} = { required => 1, description => 'Logon' };
  }
  if (grep $_ eq 'email', @fields) {
    $valid{email} = { required => 1, rules => 'email', description => 'email' };
  }
  for my $field (@fields) {
    $valid{$field} ||= { description => $field };
  }
  my $validator = DevHelp::Validate::Hash->new
    (cfg => $cfg, section => $spec->{section}, fields => \%valid, rules => {});
  my %seen;
  my @rows;
  for my $line (@lines) {
    my @data = _split_line($line, $sep);
    push @data, '' while @data < @fields;
    my %data;
    @data{@fields} = @data;
    delete $data{"x"}; # don't store ignored columns

    my %errors;
    $validator->validate(\%data, \%errors);
    my $user;
    unless ($errors{$key}) {
      if ($key eq 'id') {
	$user = SiteUsers->getByPkey($data{$key});
      }
      else {
	$user = SiteUsers->getBy(userId => $data{$key});
      }
      unless ($user) {
	$errors{$key} = "Could not find record for user $key=$data{$key}";
      }
    }
    unless ($errors{$key}) {
      if ($seen{$data{$key}}++) {
	$errors{$key} = "Duplicate record for $key = $data{$key}";
      }
    }
    if ($user && !$errors{email} && $data{email}) {
      my $checkemail = SiteUser->generic_email($data{email});
      require BSE::EmailBlacklist;
      my $blackentry = BSE::EmailBlacklist->getEntry($checkemail);
      $blackentry and
	$errors{email} = "Email $data{email} is blacklisted: $blackentry->{why}";
    }
    keys %errors and $data{errors} = \%errors;

    push @rows, \%data;
  }

  return @rows;
}

sub _split_line {
  my ($line, $sep) = @_;

  my @row;
  while ($line ne '') {
    if ($line =~ s/^"((?:[^\"]|\"\")*)"(?:$sep|$)//) {
      (my $item = $1) =~ s/\"\"/\"/g;
      push @row, $item;
    }
    elsif ($line =~ s/^([^$sep]*)(?:$sep|$)//) {
      push @row, $1;
    }
  }
  
  @row;
}


1;
