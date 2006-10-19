package BSE::Edit::Seminar;
use strict;
use base 'BSE::Edit::Product';
use BSE::TB::Seminars;
use BSE::Util::Tags qw(tag_hash tag_hash_mbcs tag_hash_plain);
use BSE::Util::SQL qw(now_sqldatetime);
use DevHelp::Date qw(dh_parse_date_sql dh_parse_time_sql);
use constant SECT_SEMSESSION_VALIDATION => 'BSE Seminar Session Validation';
use DevHelp::HTML qw(escape_html);
use BSE::Util::Iterate;

sub article_actions {
  my ($self) = @_;

  return
    (
     $self->SUPER::article_actions(),
     a_addsemsession => 'req_addsemsession',
     a_editsemsession => 'req_editsemsession',
     a_savesemsession => 'req_savesemsession',
     a_askdelsemsession => 'req_askdelsemsession',
     a_delsemsession => 'req_delsemsession',
     a_takesessionrole => 'req_takesessionrole',
     a_takesessionrolesave => 'req_takesessionrolesave',
     a_semsessionbookings => 'req_semsessionbookings',
    );
}

sub edit_template { 
  my ($self, $article, $cgi) = @_;

  my $base = 'seminar';
  my $t = $cgi->param('_t');
  if ($t && $t =~ /^\w+$/) {
    $base = $t;
  }
  return $self->{cfg}->entry('admin templates', $base, 
			     "admin/edit_$base");
}

sub generator { "BSE::Generate::Seminar" }

sub default_template {
  my ($self, $article, $cfg, $templates) = @_;

  my $template = $cfg->entry('seminars', 'template');
  return $template
    if $template && grep $_ eq $template, @$templates;

  return $self->SUPER::default_template($article, $cfg, $templates);
}

sub flag_sections {
  my ($self) = @_;

  return ( 'seminar flags', $self->SUPER::flag_sections );
}

sub type_default_value {
  my ($self, $req, $col) = @_;

  my $value = $req->cfg->entry('seminar defaults', $col);
  defined $value and return $value;

  return $self->SUPER::type_default_value($req, $col);
}

sub add_template { 
  my ($self, $article, $cgi) = @_;

  return $self->{cfg}->entry('admin templates', 'add_seminar', 
			     'admin/edit_seminar');
}

sub table_object {
  my ($self, $articles) = @_;

  'BSE::TB::Seminars';
}

sub low_edit_tags {
  my ($self, $acts, $req, $article, $articles, $msg, $errors) = @_;

  my $cfg = $req->cfg;
  my $mbcs = $cfg->entry('html', 'mbcs', 0);
  my $tag_hash = $mbcs ? \&tag_hash_mbcs : \&tag_hash;
  my $cur_session;
  my $it = BSE::Util::Iterate->new;
  return 
    (
     seminar => [ $tag_hash, $article ],
     $self->SUPER::low_edit_tags($acts, $req, $article, $articles, $msg,
				$errors),
     $it->make_iterator
     ([ \&iter_sessions, $article, $req ], 'session', 'sessions', 
      undef, undef, undef, \$cur_session),
     $it->make_iterator
     ([ \&iter_locations, $article ], 'location', 'locations'),
     ifSessionRemovable => [ \&tag_ifSessionRemovable, \$cur_session ],
    );
}

sub tag_ifSessionRemovable {
  my ($rcur_session) = @_;

  $$rcur_session or return 0;

  $$rcur_session->{when_at} gt now_sqldatetime();
}

sub iter_sessions {
  my ($seminar, $req, $args) = @_;

  my $which = $args || $req->cgi->param('s') || '';

  $seminar->{id} or return;

  my @sessions = $seminar->session_info;

  # synthesize the past entry
  my $sql_now = now_sqldatetime();
  for my $session (@sessions) {
    $session->{past} = $session->{when_at} lt $sql_now ? 1 : 0;
  }

  if ($which ne 'all') {
    @sessions = grep !$_->{past}, @sessions;
  }

  @sessions;
}

sub iter_locations {
  my ($seminar, $req, $args) = @_;

  $args ||= '';

  require BSE::TB::Locations;
  my @locations = BSE::TB::Locations->all;
  unless ($args eq 'all') {
    @locations = grep !$_->{disabled}, @locations;
  }

  @locations;
}

sub get_article {
  my ($self, $articles, $article) = @_;

  return BSE::TB::Seminars->getByPkey($article->{id});
}

my %defaults =
  (
   duration => 60,
  );

sub default_value {
  my ($self, $req, $article, $col) = @_;

  my $value = $self->SUPER::default_value($req, $article, $col);
  defined $value and return $value;

  exists $defaults{$col} and return $defaults{$col};

  return;
}

sub _fill_seminar_data {
  my ($self, $req, $data, $src) = @_;

  if (exists $src->{duration}) {
    $data->{duration} = $src->{duration};
  }
}

sub fill_new_data {
  my ($self, $req, $data, $articles) = @_;

  $self->_fill_seminar_data($req, $data, $data);

  return $self->SUPER::fill_new_data($req, $data, $articles);
}

sub fill_old_data {
  my ($self, $req, $article, $src) = @_;

  $self->_fill_seminar_data($req, $article, $src);

  return $self->SUPER::fill_old_data($req, $article, $src);
}

sub _validate_common {
  my ($self, $data, $articles, $errors) = @_;

  my $duration = $data->{duration};
  if (defined $duration && $duration !~ /^\d+\s*$/) {
    $errors->{duration} = "Duration invalid";
  }

  return $self->SUPER::_validate_common($data, $articles, $errors);
}

my %session_fields =
  (
   location_id => { description => "Location", 
		    rules=>"required;positiveint" },
   when_at_date => { description => "Date",
		     rules => "required;futuredate" },
   when_at_time => { description => "Time",
		     rules => "required;time" },
  );

sub req_addsemsession {
  my ($self, $req, $article, $articles) = @_;

  my $cgi = $req->cgi;

  my %fields = %session_fields;
  my %errors;
  $req->validate(errors=>\%errors, 
		 fields=>\%fields,
		 section=>SECT_SEMSESSION_VALIDATION);
  my $location_id;
  my $location;
  unless ($errors{location_id}) {
    require BSE::TB::Locations;

    $location_id = $cgi->param('location_id');
    $location = BSE::TB::Locations->getByPkey($location_id)
      or $errors{location_id} = "Unknown location";
  }
  my $when;
  unless (keys %errors) {
    require BSE::TB::SeminarSessions;
    my $date = dh_parse_date_sql($cgi->param('when_at_date'));
    my $time = dh_parse_time_sql($cgi->param('when_at_time'));
    $when = "$date $time";

    my ($existing) = BSE::TB::SeminarSessions->getBy(location_id=>$location_id,
						   when_at=>$when);
    if ($existing) {
      $errors{location_id} = $errors{when_at_date} =
	$errors{when_at_time} = "A session is already booked for that date and time at this location";
    }
  }
  keys %errors
    and return $self->edit_form($req, $article, $articles, undef, \%errors);

  my $session = $article->add_session($when, $location);

  return $self->refresh($article, $cgi, undef, 'Session added');
}

sub _get_session {
  my ($req, $article, $rmsg) = @_;

  my $cgi = $req->cgi;
  my $session_id = $cgi->param('session_id');
  defined $session_id && $session_id =~ /^\d+$/
    or do { $$rmsg = "Missing or invalid session id"; return; };
  require BSE::TB::SeminarSessions;
  my $session = BSE::TB::SeminarSessions->getByPkey($session_id)
    or do { $$rmsg = "Unknown session $session_id"; return; };
  $session->{seminar_id} == $article->{id}
    or do { $$rmsg = "Session does not belong to this seminar"; return };
  
  return $session;
}

sub req_editsemsession {
  my ($self, $req, $article, $articles, $errors) = @_;

  my $cgi = $req->cgi;
  my $msg;
  my $session = _get_session($req, $article, \$msg)
    or return $self->edit_form($req, $article, $articles, $msg);

  my %fields = %session_fields;
  my $cfg_fields = $req->configure_fields(\%fields, SECT_SEMSESSION_VALIDATION);
  
  my %acts;
  %acts =
    (
     $self->low_edit_tags(\%acts, $req, $article, undef, $errors),
     field => [ \&tag_field, $cfg_fields ],
     session => [ \&tag_hash, $session ],
    );

  return $req->dyn_response('admin/semsessionedit.tmpl', \%acts);
}

sub req_savesemsession {
  my ($self, $req, $article, $articles) = @_;

  my $cgi = $req->cgi;
  my $msg;
  my $session = _get_session($req, $article, \$msg)
    or return edit_form($req, $article, $articles, $msg);

  my %fields = %session_fields;
  my %errors;
  $req->validate(errors=>\%errors, 
		 fields=>\%fields,
		 section=>SECT_SEMSESSION_VALIDATION);
  my $location_id;
  my $location;
  unless ($errors{location_id}) {
    require BSE::TB::Locations;

    $location_id = $cgi->param('location_id');
    $location = BSE::TB::Locations->getByPkey($location_id)
      or $errors{location_id} = "Unknown location";
  }
  my $when;
  unless (keys %errors) {
    require BSE::TB::SeminarSessions;
    my $date = dh_parse_date_sql($cgi->param('when_at_date'));
    my $time = dh_parse_time_sql($cgi->param('when_at_time'));
    $when = "$date $time";

    my ($existing) = BSE::TB::SeminarSessions->getBy(location_id=>$location_id,
						   when_at=>$when);
    if ($existing && $existing->{session_id} != $session->{session_id}) {
      $errors{location_id} = $errors{when_at_date} =
	$errors{when_at_time} = "A session is already booked for that date and time at this location";
    }
  }
  keys %errors
    and return $self->edit_form($req, $article, $articles, undef, \%errors);

  my $old_location_id = $session->{location_id};
  my $old_when = $session->{when_at};
  $session->{location_id} = $location_id;
  $session->{when_at} = $when;
  $session->save;

  my @msgs = 'Seminar session saved';

  if ($cgi->param('notify') 
      && ($session->{location_id} != $old_location_id
	  || $session->{when_at} ne $old_when)) {
    my $old_location = BSE::TB::Locations->getByPkey($old_location_id);
    my @bookings = $session->booked_users();
    my $notify_sect = 'Session Change Notification';
    require BSE::Mail;
    my $cfg = $req->cfg;
    my $mailer = BSE::Mail->new(cfg=>$cfg);
    my $from = $cfg->entry($notify_sect, 'from',
			   $cfg->entry('shop', 'from', $Constants::SHOP_FROM));
    my @errors;
    my $sent;
    for my $user (@bookings) {
      my %acts;
      %acts = 
	(
	 session => [ \&tag_hash_plain, $session ],
	 seminar => [ \&tag_hash_plain, $article ],
	 old_when => $old_when,
	 old_location => [ \&tag_hash_plain, $old_location ],
	 location => [ \&tag_hash_plain, $location ],
	);

      if ($mailer->complex_mail(from=>$from, 
				to=>$user->{email},
				template=>'user/sessionchangenotify',
				acts=>\%acts,
				section=>$notify_sect,
				subject=>'Session Rescheduled')) {
	++$sent;
      }
      else {
	push @errors, "Error sending notification to $user->{email}:"
	  . $mailer->errstr;
      }
    }

    if (@bookings) {
      if ($sent) {
	$msgs[0] .= " ($sent users notified by email about the change)";
	if (@errors > 5) {
	  # something really wrong, dump them to the error log and trim the list
	  print STDERR $_ for @errors;
	  my $total = @errors;
	  splice @errors, 5;
	  push @errors, "(more errors omitted - total of $total errors)";
	}
	push @msgs, @errors;
      }
    }
    else {
      $msgs[0] .= ' (No users were booked for this session to be notified)';
    }
  }

  return $self->refresh($article, $cgi, undef, \@msgs);
}

sub iter_other_sessions {
  my ($seminar, $session) = @_;

  grep $_->{id} != $session->{id}, $seminar->future_sessions;
}

sub tag_other_location {
  my ($rcur_session, $arg) = @_;

  $$rcur_session or return '';
  my $location = $$rcur_session->location;

  my $value = $location->{$arg};
  defined $value or return '';

  escape_html($value);
}

sub req_askdelsemsession {
  my ($self, $req, $article, $articles, $errors) = @_;

  my $cgi = $req->cgi;
  my $msg;
  my $session = _get_session($req, $article, \$msg)
    or return $self->edit_form($req, $article, $articles, $msg);

  my %fields = %session_fields;
  my $cfg_fields = $req->configure_fields(\%fields, SECT_SEMSESSION_VALIDATION);
  my $location = $session->location;
  
  my $it = BSE::Util::Iterate->new;
  my %acts;
  my $cur_session;
  %acts =
    (
     $self->low_edit_tags(\%acts, $req, $article, $articles, undef, $errors),
     field => [ \&tag_field, $cfg_fields ],
     session => [ \&tag_hash, $session ],
     location => [ \&tag_hash, $location ],
     $it->make_iterator
     ([ \&iter_other_sessions, $article, $session ], 
      'other_session', 'other_sessions', undef, undef, undef, \$cur_session),
     other_location => [ \&tag_other_location, \$cur_session ],
    );

  return $req->dyn_response('admin/semsessiondel', \%acts);
}

sub req_delsemsession {
  my ($self, $req, $article, $articles) = @_;

  my $cgi = $req->cgi;
  my $msg;
  my $session = _get_session($req, $article, \$msg)
    or return $self->edit_form($req, $article, $articles, $msg);

  my %errors;

  # which session are bookings moving to
  my $other_session_id = $cgi->param('othersession_id');
  my $other_session;
  if ($other_session_id) {
    if ($other_session_id != -1) {
      $other_session = BSE::TB::SeminarSessions->getByPkey($other_session_id);
      if (!$other_session 
	  || $other_session->{seminar_id} != $article->{id}
	  || $other_session->{id} == $session->{id}) {
	$errors{othersession_id} = "Invalid alternate section selected";
      }
    }
  }
  else {
    $errors{othersession_id} = "Please select cancel or the session to move bookings to";
  }

  keys %errors
    and return $self->req_askdelsemsession($req, $article, $articles, \%errors);

  my %session = %$session;

  my @msgs = 'Seminar session deleted';

  if ($cgi->param('notify')) {
    my $location = $session->location;
    my @bookings = $session->booked_users();
    my $notify_sect = 'Session Change Notification';
    require BSE::Mail;
    my $cfg = $req->cfg;
    my $mailer = BSE::Mail->new(cfg=>$cfg);
    my $from = $cfg->entry($notify_sect, 'from',
			   $cfg->entry('shop', 'from', $Constants::SHOP_FROM));
    my @errors;
    my $sent;
    for my $user (@bookings) {
      my %acts;
      %acts = 
	(
	 session => [ \&tag_hash_plain, $session ],
	 seminar => [ \&tag_hash_plain, $article ],
	 location => [ \&tag_hash_plain, $location ],
	 ifCancelled => $other_session_id == -1,
	);
      my $subject;
      if ($other_session) {
	$subject = "Session Merged";
	$acts{new_session} = [ \&tag_hash_plain, $other_session ];
	$acts{new_location} = [ \&tag_hash_plain, $other_session->location ],
      }
      else {
	$subject = "Session Cancelled";
      }

      if ($mailer->complex_mail(from=>$from, 
				to=>$user->{email},
				template=>'user/sessiondeletenotify',
				acts=>\%acts,
				section=>$notify_sect,
				subject=>$subject)) {
	++$sent;
      }
      else {
	push @errors, "Error sending notification to $user->{email}:"
	  . $mailer->errstr;
      }
    }

    if (@bookings) {
      if ($sent) {
	$msgs[0] .= " ($sent users notified by email about the change)";
	if (@errors > 5) {
	  # something really wrong, dump them to the error log and trim the list
	  print STDERR $_ for @errors;
	  my $total = @errors;
	  splice @errors, 5;
	  push @errors, "(more errors omitted - total of $total errors)";
	}
	push @msgs, @errors;
      }
    }
    else {
      $msgs[0] .= ' (No users were booked for this session to be notified)';
    }
  }

  if ($other_session) {
    $session->replace_with($other_session_id);
  }
  else {
    $session->cancel;
  }

  return $self->refresh($article, $cgi, undef, \@msgs);
}

sub req_takesessionrole {
  my ($self, $req, $article, $articles, $errors) = @_;

  my $cgi = $req->cgi;
  my $msg;
  my $session = _get_session($req, $article, \$msg)
    or return $self->edit_form($req, $article, $articles, $msg);

  my @roll_call = $session->roll_call_entries;
  my %acts;
  my $it = BSE::Util::Iterate->new;
  %acts =
    (
     $self->low_edit_tags(\%acts, $req, $article, $articles, undef, $errors),
     $it->make_iterator(undef, 'rolluser', 'rollusers', \@roll_call),
     session=>[ \&tag_hash, $session ],
    );

  return $req->dyn_response('admin/semsessionrollcall', \%acts);
}

sub req_takesessionrolesave {
  my ($self, $req, $article, $articles) = @_;

  my $cgi = $req->cgi;
  my $msg;
  my $session = _get_session($req, $article, \$msg)
    or return $self->edit_form($req, $article, $articles, $msg);

  my @roll_call = $session->roll_call_entries;

  for my $userid (map $_->{id}, @roll_call) {
    my $there = $cgi->param("roll_present_$userid");
    $session->set_roll_present($userid, $there);
  }
  $session->{roll_taken} = 1;
  $session->save;

  return $self->refresh($article, $cgi, undef, "Roll saved");
}

sub req_semsessionbookings {
  my ($self, $req, $article, $articles, $errors) = @_;

  my $cgi = $req->cgi;
  my $msg;
  my $session = _get_session($req, $article, \$msg)
    or return $self->edit_form($req, $article, $articles, $msg);

  my @roll_call = $session->roll_call_entries;
  my %acts;
  my $it = BSE::Util::Iterate->new;
  %acts =
    (
     $self->low_edit_tags(\%acts, $req, $article, $articles, undef, $errors),
     $it->make_iterator(undef, 'bookeduser', 'bookedusers', \@roll_call),
     session=>[ \&tag_hash, $session ],
    );

  return $req->dyn_response('admin/semsessionbookings', \%acts);
}

sub base_template_dirs {
  return ( "seminars" );
}

sub extra_templates {
  my ($self, $article) = @_;

  my @extras;

  my $extras = $self->{cfg}->entry('seminars', 'extra_templates');
  push @extras, grep /\.(tmpl|html)$/i, split /,/, $extras
    if $extras;

  return @extras;
}

1;

