package BSE::UI::AdminSeminar;
use strict;
use base qw(BSE::UI::AdminDispatch);
use BSE::Util::Tags qw(tag_hash tag_error_img tag_hash_plain);
use BSE::Util::DynSort qw(sorter tag_sorthelp);
use BSE::Template;
use BSE::Util::Iterate;
use BSE::TB::Locations;
use BSE::Util::HTML qw(:default popup_menu);
use constant SECT_LOCATION_VALIDATION => "BSE Location Validation";
use BSE::CfgInfo 'product_options';
use DevHelp::Date qw(dh_strftime_sql_datetime);

our $VERSION = "1.002";

my %rights =
  (
   loclist		 => 'bse_location_list',
   locaddform		 => 'bse_location_add',
   locadd		 => 'bse_location_add',
   locedit		 => 'bse_location_edit',
   locsave		 => 'bse_location_edit',
   locview		 => 'bse_location_view',
   locdelask		 => 'bse_location_delete',
   locdelete		 => 'bse_location_delete',
   #    detail		 => 'bse_subscr_detail',
   #    update		 => 'bse_subscr_update',
   addattendseminar	 => 'bse_session_booking_add',
   addattendsession	 => 'bse_session_booking_add',
   addattendsave	 => 'bse_session_booking_add',
   cancelbookingconfirm	 => 'bse_session_booking_cancel',
   cancelbooking	 => 'bse_session_booking_cancel',
   editbooking   	 => 'bse_session_booking_edit',
   savebooking	         => 'bse_session_booking_edit',
  );

sub actions { \%rights }

sub rights { \%rights }

sub default_action { 'loclist' }

sub req_loclist {
  my ($class, $req, $errors) = @_;

  my $msg = $req->message($errors);
  my $cgi = $req->cgi;
  my @locations = BSE::TB::Locations->all;
  my ($sortby, $reverse) =
    sorter(data=>\@locations, cgi=>$cgi, sortby=>'description', 
	   session=>$req->session,
           name=>'locations', fields=> { id => {numeric => 1 } });
  my $it = BSE::Util::Iterate->new;
  my $current_loc;

  my %acts;
  %acts =
    (
     $req->admin_tags,
     msg => $msg,
     message => $msg,
     $it->make_paged_iterator('ilocation', 'locations', \@locations, undef,
                              $cgi, undef, 'pp=20', $req->session, 
                              'locations', \$current_loc),
     sorthelp => [ \&tag_sorthelp, $sortby, $reverse ],
     sortby=>$sortby,
     reverse=>$reverse,
     ifRemovable => [ \&tag_ifRemovable, \$current_loc ],
    );

  return $req->dyn_response('admin/locations/list', \%acts);
}

sub tag_ifRemovable {
  my ($rlocation) = @_;

  $$rlocation or return;

  $$rlocation->is_removable;
}

sub tag_field {
  my ($fields, $args) = @_;

  my ($name, $parm) = split ' ', $args;

  exists $fields->{$name}
    or return "** Unknown field $name **";
  exists $fields->{$name}{$parm}
    or return '';

  return escape_html($fields->{$name}{$parm});
}

sub req_locaddform {
  my ($class, $req, $errors) = @_;

  my $msg = $req->message($errors);

  my %fields = BSE::TB::Location->valid_fields();
  my $cfg_fields = $req->configure_fields(\%fields, SECT_LOCATION_VALIDATION);

  my %acts;
  %acts =
    (
     $req->admin_tags,
     msg => $msg,
     message => $msg,
     error_img => [ \&tag_error_img, $req->cfg, $errors ],
     field => [ \&tag_field, $cfg_fields ],
    );

  return $req->dyn_response('admin/locations/add', \%acts);
}

sub req_locadd {
  my ($class, $req) = @_;

  my $cgi = $req->cgi;
  my $cfg = $req->cfg;
  my %fields = BSE::TB::Location->valid_fields($cfg);
  my %rules = BSE::TB::Location->valid_rules($cfg);
  my %errors;
  $req->validate(errors=> \%errors, 
		 fields=> \%fields,
		 rules => \%rules,
		 section => SECT_LOCATION_VALIDATION);

  keys %errors
    and return $class->req_locaddform($req, \%errors);

  my %location;
  for my $field (keys %fields) {
    $location{$field} = $cgi->param($field);
  }
  $location{disabled} = 0;
  my @cols = BSE::TB::Location->columns;
  shift @cols;
  my $loc = BSE::TB::Locations->add(@location{@cols});

  my $r = $class->_loclist_refresh($req, "Location $location{description} added");

  return BSE::Template->get_refresh($r, $req->cfg);
}

sub _loc_show_common {
  my ($class, $req, $errors, $template) = @_;

  my $loc_id = $req->cgi->param('id');
  $loc_id && $loc_id =~ /^\d+/
    or return $class->req_loclist
      ($req, { id=>'Missing or invalid location id' });
  my $location = BSE::TB::Locations->getByPkey($loc_id);
  $location
    or return $class->req_loclist
      ($req, { id=>'Unknown location id' });

  my $msg = $req->message($errors);

  my %fields = BSE::TB::Location->valid_fields();
  my $cfg_fields = $req->configure_fields(\%fields, SECT_LOCATION_VALIDATION);

  my $it = BSE::Util::Iterate->new;

  my %acts;
  %acts =
    (
     $req->admin_tags,
     msg => $msg,
     message => $msg,
     error_img => [ \&tag_error_img, $req->cfg, $errors ],
     location => [ \&tag_hash, $location ],
     field => [ \&tag_field, $cfg_fields ],
     $it->make_iterator([ \&iter_locsessions, $location ],
			'session', 'sessions'),
    );

  return $req->dyn_response($template, \%acts);
}

sub iter_locsessions {
  my ($location) = @_;

  $location->sessions_detail;
}

sub req_locedit {
  my ($class, $req, $errors) = @_;

  return $class->_loc_show_common($req, $errors, 'admin/locations/edit');
}

sub req_locsave {
  my ($class, $req) = @_;

  my $loc_id = $req->cgi->param('id');
  $loc_id && $loc_id =~ /^\d+/
    or return $class->req_loclist
      ($req, { id=>'Missing or invalid location id' });
  my $location = BSE::TB::Locations->getByPkey($loc_id);
  $location
    or return $class->req_loclist
      ($req, { id=>'Unknown location id' });

  my $cgi = $req->cgi;
  my $cfg = $req->cfg;
  my %fields = $location->valid_fields($cfg);
  my %rules = $location->valid_rules($cfg);
  my %errors;
  $req->validate(errors=> \%errors, 
		 fields=> \%fields,
		 rules => \%rules,
		 section => SECT_LOCATION_VALIDATION);

  keys %errors
    and return $class->req_locedit($req, \%errors);

  for my $field (keys %fields) {
    my $value = $cgi->param($field);
    $location->{$field} = $value if defined $value;
  }

  if ($cgi->param('save_disabled')) {
    $location->{disabled} = $cgi->param('disabled') ? 1 : 0;
  }

  $location->save;

  my $r = $class->_loclist_refresh($req, 
				   "Location $location->{description} saved");

  return BSE::Template->get_refresh($r, $req->cfg);
}

sub req_locview {
  my ($class, $req, $errors) = @_;

  return $class->_loc_show_common($req, $errors, 'admin/locations/view');
}

sub req_locdelask {
  my ($class, $req, $errors) = @_;

  return $class->_loc_show_common($req, $errors, 'admin/locations/delete');
}

sub req_locdelete {
  my ($class, $req) = @_;

  my $loc_id = $req->cgi->param('id');
  $loc_id && $loc_id =~ /^\d+/
    or return $class->req_loclist
      ($req, { id=>'Missing or invalid location id' });
  my $location = BSE::TB::Locations->getByPkey($loc_id);
  $location
    or return $class->req_loclist
      ($req, { id=>'Unknown location id' });

  $location->is_removable
    or return $class->req_loclist
      ($req, { id=>"Location $location->{description} cannot be removed" });

  my $description = $location->{description};
  $location->remove;

  my $r = $class->_loclist_refresh($req, 
				   "Location $description removed");

  return BSE::Template->get_refresh($r, $req->cfg);
}

sub _loclist_refresh {
  my ($class, $req, $msg) = @_;

  my $r = $req->cgi->param('r') || $req->cgi->param('refreshto');
  unless ($r) {
    $r = "/cgi-bin/admin/admin_seminar.pl";
  }
  if ($msg && $r !~ /[&?]m=/) {
    my $sep = $r =~ /\?/ ? '&' : '?';

    $r .= $sep . "m=" . escape_uri($msg);
  }

  return $r;
}

sub req_addattendseminar {
  my ($class, $req, $errors) = @_;

  # make sure we're passed a valid siteuser_id
  my $cgi = $req->cgi;
  my $siteuser_id = $cgi->param('siteuser_id');
  defined $siteuser_id && $siteuser_id =~ /^\d+$/
    or return $class->req_loclist($req, { siteuser_id => 
					  "Missing or invalid siteuser_id" });
  require BSE::TB::SiteUsers;
  my $siteuser = BSE::TB::SiteUsers->getByPkey($siteuser_id)
    or return $class->req_loclist($req, { siteuser_id => "Unknown siteuser_id" });
  my $msg = $req->message($errors);
  require BSE::TB::Seminars;
  my @seminars = BSE::TB::Seminars->all;

  my $it = BSE::Util::Iterate->new;
  my %acts;
  %acts =
    (
     $req->admin_tags,
     $it->make_iterator(undef, 'seminar', 'seminars', \@seminars),
     siteuser => [ \&tag_hash, $siteuser ],
     msg => $msg,
     message => $msg,
     error_img => [ \&tag_error_img, $req->cfg, $errors ],
    );
  
  return $req->dyn_response('admin/addattendee1', \%acts);
}

sub req_addattendsession {
  my ($class, $req, $errors) = @_;

  # make sure we're passed a valid siteuser_id
  my $cgi = $req->cgi;
  my $siteuser_id = $cgi->param('siteuser_id');
  defined $siteuser_id && $siteuser_id =~ /^\d+$/
    or return $class->req_loclist($req, { siteuser_id => 
					  "Missing or invalid siteuser_id" });
  require BSE::TB::SiteUsers;
  my $siteuser = BSE::TB::SiteUsers->getByPkey($siteuser_id)
    or return $class->req_loclist($req, { siteuser_id => "Unknown siteuser_id" });

  # make sure we got a valid seminar
  require BSE::TB::Seminars;
  my $seminar_id = $cgi->param('seminar_id');
  defined $seminar_id && $seminar_id =~ /^\d*$/
    or return $class->req_addattendseminar
      ($req, { seminar_id => "Missing or invalid seminar_id" });
  $seminar_id
    or return $class->req_addattendseminar
      ($req, { seminar_id => "Please select a seminar" });
  my $seminar = BSE::TB::Seminars->getByPkey($seminar_id)
    or return $class->req_addattendseminar
      ($req, { seminar_id => "Unknown seminar_id" });
  my $msg = $req->message($errors);

  my @sem_options = _get_sem_options($req->cfg, $seminar);
  my $current_option;

  my @sessions = $seminar->session_info;
  my %user_booked = map { $_=>1 } 
    $siteuser->seminar_sessions_booked($seminar_id);
  @sessions = grep !$user_booked{$_->{id}}, @sessions;

  my $it = BSE::Util::Iterate->new;
  my %acts;
  %acts =
    (
     $req->admin_tags,
     siteuser => [ \&tag_hash, $siteuser ],
     seminar => [ \&tag_hash, $seminar ],
     msg => $msg,
     message => $msg,
     error_img => [ \&tag_error_img, $req->cfg, $errors ],
     $it->make_iterator(undef, 'session', 'sessions', \@sessions),
     $it->make_iterator(undef, 'option', 'options', \@sem_options, 
			undef, undef, \$current_option),
     option_popup => [ \&tag_option_popup, $req->cgi, \$current_option ],
    );
  
  return $req->dyn_response('admin/addattendee2', \%acts);
}

sub tag_option_popup {
  my ($cgi, $roption) = @_;

  $$roption 
    or return '** popup_option not in options iterator **';

  my $option = $$roption;

  my @extras;
  my $value = $cgi->param($option->{id});
  defined $value or $value = $option->{value};
  if ($value) {
    push @extras, -default => $value;
  }

  return popup_menu(-name => $option->{id},
		    -values => $option->{values},
		    -labels => $option->{labels},
		    @extras);
}

sub req_addattendsave {
  my ($class, $req, $errors) = @_;

  # make sure we're passed a valid siteuser_id
  my $cgi = $req->cgi;
  my $siteuser_id = $cgi->param('siteuser_id');
  defined $siteuser_id && $siteuser_id =~ /^\d+$/
    or return $class->req_loclist($req, { siteuser_id => 
					  "Missing or invalid siteuser_id" });
  require BSE::TB::SiteUsers;
  my $siteuser = BSE::TB::SiteUsers->getByPkey($siteuser_id)
    or return $class->req_loclist($req, { siteuser_id => "Unknown siteuser_id" });

  # make sure we got a valid seminar
  require BSE::TB::Seminars;
  my $seminar_id = $cgi->param('seminar_id');
  defined $seminar_id && $seminar_id =~ /^\d*$/
    or return $class->req_addattendseminar
      ($req, { seminar_id => "Missing or invalid seminar_id" });
  $seminar_id
    or return $class->req_addattendseminar
      ($req, { seminar_id => "Please select a seminar" });
  my $seminar = BSE::TB::Seminars->getByPkey($seminar_id)
    or return $class->req_addattendseminar
      ($req, { seminar_id => "Unknown seminar_id" });
  my $msg = $req->message($errors);

  # make sure we get a valid session
  require BSE::TB::SeminarSessions;
  my $session_id = $cgi->param('session_id');
  defined $session_id && $session_id =~ /^\d*$/
    or return $class->req_addattendsession
      ($req, { session_id => "Missing or invalid session_id" });
  $session_id
    or return $class->req_addattendsession
      ($req, { session_id => "Please select a session" });
  my $session = BSE::TB::SeminarSessions->getByPkey($session_id)
    or return $class->req_addattendsession
      ($req, { session_id => "Unknown session_id" });

  # accumulate the options
  my %errors;
  my @options;
  for my $opt_name (split /,/, $seminar->{options}) {
    my $value = $cgi->param($opt_name);
    defined $value
      or return $class->req_addattendsession
	($req, { opt_name => "Missing value for $opt_name" });
    
    push @options, $value;
  }

  my %more;
  for my $name (qw/customer_instructions support_notes roll_present/) {
    my $value = $cgi->param($name);
    $value and $more{$name} = $value;
  }
  $more{roll_present} ||= 0;
  $more{options}      = join(',', @options);

  eval {
    $session->add_attendee($siteuser, %more);
  };
  if ($@) {
    if ($@ =~ /duplicate/i) {
      return $class->req_addattendsession
	($req, { session_id => "User already booked for this session" });
    }
    else {
      return $class->req_addattendsession
	($req, { _error => $@ });
    }
  }

  require BSE::ComposeMail;
  my $cfg = $req->cfg;
  my $mailer = BSE::ComposeMail->new(cfg => $cfg);
  my $subject = $cfg->entry('seminars', 'booked_notify_subject',
			    'You have been booked for seminar');
  my @sem_options = _get_sem_options($cfg, $seminar, @options);
  my $it = DevHelp::Tags::Iterate->new;
  my %acts;
  %acts =
    (
     BSE::Util::Tags->static(undef, $cfg),
     user     => [ \&tag_hash_plain, $siteuser ],
     seminar  => [ \&tag_hash_plain, $seminar  ],
     session  => [ \&tag_hash_plain, $session  ],
     booking  => [ \&tag_hash_plain, \%more    ],
     location => [ \&tag_hash_plain, $session->location ],
     $it->make_iterator(undef, 'option', 'options', \@sem_options),
    );

  unless ($mailer->send(to	  => $siteuser,
			subject	  => $subject,
			template  => 'user/admin_book_seminar',
			acts	  => \%acts)) {
    return $class->req_addattendsession
	($req, { _email => "The user has been booked, but there was an error seding the email notification:".$mailer->errstr });
  }

  
  my $r = $cgi->param('r');
  unless ($r) {
    $r = "/cgi-bin/admin/siteusers.pl?a_edit=1&id=" . $siteuser->{id};
  }

  return BSE::Template->get_refresh($r, $req->cfg);
}

sub req_cancelbookingconfirm {
  my ($class, $req, $message) = @_;

  my $cgi = $req->cgi;

  my $id = $cgi->param('id');
  defined $id && $id =~ /^\d+$/
    or return $class->error($req, "id parameter invalid");

  require BSE::TB::SeminarBookings;
  my $booking = BSE::TB::SeminarBookings->getByPkey($id)
    or return $class->error($req, "booking $id not found");

  my $session = $booking->session;
  my $siteuser = $booking->siteuser;

  my $seminar = $session->seminar;
  my @sem_options = _get_sem_options($req->cfg, $seminar, 
				     split /,/, $session->{options});

  defined $message or $message = '';
  $message = escape_html($message);

  my $it = BSE::Util::Iterate->new;
  my %acts;
  %acts =
    (
     $req->admin_tags,
     siteuser => [ \&tag_hash, $siteuser ],
     session  => [ \&tag_hash, $session  ],
     seminar  => [ \&tag_hash, $seminar ],
     location => [ \&tag_hash, $session->location ],
     booking  => [ \&tag_hash, $booking  ],
     message  => $message,
     $it->make_iterator(undef, 'option', 'options', \@sem_options),
    );

  return $req->dyn_response('admin/semcancelbooking', \%acts);
}

sub req_cancelbooking {
  my ($class, $req) = @_;

  my $cgi = $req->cgi;

  my $id = $cgi->param('id');
  defined $id && $id =~ /^\d+$/
    or return $class->error($req, "id parameter invalid");

  require BSE::TB::SeminarBookings;
  my $booking = BSE::TB::SeminarBookings->getByPkey($id)
    or return $class->error($req, "booking $id not found");

  my $session = $booking->session;
  my $siteuser = $booking->siteuser;

  my @options = split /,/, $booking->{options};
  local $SIG{__DIE__};
  eval {
    $session->remove_booking($siteuser);
  };
  $@ and return $class->req_cancelbookingconfirm
    ($req, "Could not remove booking $@");

  my $seminar = $session->seminar;

  my @sem_options = _get_sem_options($req->cfg, $seminar, @options);

  require BSE::ComposeMail;
  my $cfg = $req->cfg;
  my $mailer = BSE::ComposeMail->new(cfg => $cfg);
  my $subject = $cfg->entry('seminars', 'unbooked_notify_subject',
			    'Your seminar booking has been cancelled');
  my $it = DevHelp::Tags::Iterate->new;
  my %acts;
  %acts =
    (
     BSE::Util::Tags->static(undef, $cfg),
     user     => [ \&tag_hash_plain, $siteuser ],
     seminar  => [ \&tag_hash_plain, $seminar  ],
     session  => [ \&tag_hash_plain, $session  ],
     booking  => [ \&tag_hash_plain, $booking  ],
     location => [ \&tag_hash_plain, $session->location ],
     $it->make_iterator(undef, 'option', 'options', \@sem_options),
    );

  unless ($mailer->send(to	  => $siteuser,
			subject	  => $subject,
			template  => 'user/admin_unbook_seminar',
			acts	  => \%acts)) {
    return $class->req_cancelbookingconfirm
      ($req, "The user booking was cancelled, but there was an error sending the email notification:".$mailer->errstr );
  }

  my $r = $cgi->param('r');
  unless ($r) {
    $r = '/cgi-bin/admin/siteusers.pl?a_view=1&id='.$siteuser->{id};
  }
  $r .= $r =~ /\?/ ? '&' : '?';
  $r .= "m=Booking+cancelled";

  return BSE::Template->get_refresh($r, $req->cfg);
}

sub req_editbooking {
  my ($class, $req, $errors) = @_;

  my $cgi = $req->cgi;

  my $id = $cgi->param('id');
  defined $id && $id =~ /^\d+$/
    or return $class->error($req, "id parameter invalid");

  require BSE::TB::SeminarBookings;
  my $booking = BSE::TB::SeminarBookings->getByPkey($id)
    or return $class->error($req, "booking $id not found");

  my $session = $booking->session;

  my $siteuser = $booking->siteuser;

  my $message = $req->message($errors);

  my $seminar = $session->seminar;
  my @sem_options = _get_sem_options($req->cfg, $seminar, 
				     split /,/,  $booking->{options});
  my @unbooked = $seminar->get_unbooked_by_user($siteuser);
  @unbooked = sort { $b->{when_at} cmp $a->{when_at} } ( @unbooked, $session );
    
  my $current_option;
  my $it = BSE::Util::Iterate->new;
  my %acts;
  %acts =
    (
     $req->admin_tags,
     siteuser => [ \&tag_hash, $siteuser ],
     session  => [ \&tag_hash, $session  ],
     seminar  => [ \&tag_hash, $seminar ],
     location => [ \&tag_hash, $session->location ],
     booking  => [ \&tag_hash, $booking  ],
     message  => $message,
     error_img => [ \&tag_error_img, $req->cfg, $errors ],
     $it->make_iterator(undef, 'option', 'options', \@sem_options, 
			undef, undef, \$current_option),
     option_popup => [ \&tag_option_popup, $req->cgi, \$current_option ],
     $it->make_iterator(undef, 'isession', 'sessions', \@unbooked),
     session_popup => 
     [ \&tag_session_popup, $req->cfg, $booking, $req->cgi, \@unbooked ],
    );

  return $req->dyn_response('admin/semeditbooking', \%acts);
}

sub req_savebooking {
  my ($class, $req, $message) = @_;

  my $cgi = $req->cgi;

  my $id = $cgi->param('id');
  defined $id && $id =~ /^\d+$/
    or return $class->error($req, "id parameter invalid");

  require BSE::TB::SeminarBookings;
  my $booking = BSE::TB::SeminarBookings->getByPkey($id)
    or return $class->error($req, "booking $id not found");

  my @cols = $booking->columns;
  shift @cols;
  for my $name (@cols) {
    my $value = $cgi->param($name);
    defined $value and $booking->set($name => $value);
  }
  my $seminar = $booking->session->seminar;
  my @options;
  for my $name (split /,/, $seminar->{options}) {
    push @options, ($cgi->param($name))[0];
  }
  $booking->{options} = join ',', @options;

  eval {
    $booking->save;
  };
  $@
    and return $class->req_editbooking($req, { error => $@ });

  my @sem_options = _get_sem_options($req->cfg, $seminar, @options);

  my $session = $booking->session;
  my $siteuser = $booking->siteuser;
  require BSE::ComposeMail;
  my $cfg = $req->cfg;
  my $mailer = BSE::ComposeMail->new(cfg => $cfg);
  my $subject = $cfg->entry('seminars', 'edit_notify_subject',
			    'Your seminar booking has been changed');
  my $it = DevHelp::Tags::Iterate->new;
  my %acts;
  %acts =
    (
     BSE::Util::Tags->static(undef, $cfg),
     user     => [ \&tag_hash_plain, $siteuser ],
     seminar  => [ \&tag_hash_plain, $seminar  ],
     session  => [ \&tag_hash_plain, $session  ],
     booking  => [ \&tag_hash_plain, $booking  ],
     location => [ \&tag_hash_plain, $session->location ],
     $it->make_iterator(undef, 'option', 'options', \@sem_options),
    );

  unless ($mailer->send(to	  => $siteuser,
			subject	  => $subject,
			template  => 'user/admin_edit_seminar',
			acts	  => \%acts)) {
    return $class->req_editbooking
      ($req, _email => "The user booking was changed, but there was an error sending the email notification:".$mailer->errstr );
  }

  my $r = $cgi->param('r');
  unless ($r) {
    $r = '/cgi-bin/admin/siteusers.pl?a_view=1&id='.$siteuser->{id};
  }
  $r .= $r =~ /\?/ ? '&' : '?';
  $r .= "m=Booking+updated";

  return BSE::Template->get_refresh($r, $req->cfg);
}

sub _get_sem_options {
  my ($cfg, $seminar, @values) = @_;

  $seminar->option_descs($cfg, \@values);
}

sub tag_session_popup {
  my ($cfg, $booking, $cgi, $unbooked) = @_;

  my $default = $cgi->param('session_id');
  defined $default or $default = $booking->{session_id};
  my %locations;
  for my $session (@$unbooked) {
    unless ($locations{$session->{location_id}}) {
      $locations{$session->{location_id}} = $session->location;
    }
  }

  my $date_fmt = $cfg->entry('seminars', 'popup_date_format', 
			     "%I:%M %p %d %b %Y");
  return popup_menu
    (-name => 'session_id',
     -values => [ map $_->{id}, @$unbooked ],
     -labels => 
     { map 
       { $_->{id} => 
	   _session_desc($_, $locations{$_->{location_id}}, $date_fmt) 
	 } @$unbooked 
     },
     -default => $default);
}

sub _session_desc {
  my ($session, $location, $date_fmt) = @_;

  dh_strftime_sql_datetime($date_fmt, $session->{when_at}) . ' - ' .
    $location->{description};
}

1;
