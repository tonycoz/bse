package BSE::UI::User;
use strict;
use base 'BSE::UI::Dispatch';
use BSE::Util::Tags qw(tag_hash tag_error_img tag_hash_plain);
use DevHelp::HTML qw(:default popup_menu);
use BSE::Util::Iterate;

my %actions =
  (
   bookseminar => 1,
   bookconfirm => 1,
   book => 1,
   bookcomplete => 1,
  );

sub default_action {
  'error';
}

sub actions {
  \%actions;
}

sub req_bookseminar {
  my ($self, $req, $errors) = @_;

  my $cgi = $req->cgi;
  my $seminar_id = $cgi->param('id');
  defined $seminar_id && $seminar_id =~ /^\d+$/
    or return $self->error($req, "Seminar id parameter missing");

  require BSE::TB::Seminars;
  my $seminar = BSE::TB::Seminars->getByPkey($seminar_id)
    or return $self->error($req, "Unknown seminar");

  $seminar->{retailPrice} == 0
    or return $self->error($req, "This is only available for free seminars");

  my @sessions = $seminar->session_info_unbooked($req->siteuser);
  my $message = $req->message($errors);
  @sessions
    or $message = "You are already booked for every session of this seminar";
  my @opt_names = split /,/, $seminar->{options};
  my @opt_values = map { ($cgi->param($_))[0] } @opt_names;
  my @options = $seminar->option_descs($req->cfg, \@opt_values);

  my $it = BSE::Util::Iterate->new;
  my $current_option;
  my %acts;
  %acts =
    (
     $req->dyn_user_tags(),
     seminar => [ \&tag_hash, $seminar ],
     message => escape_html($message),
     error_img => [ \&tag_error_img, $req->cfg, $errors ],
     $it->make_iterator(undef, 'session', 'sessions', \@sessions),
     $it->make_iterator(undef, 'option', 'options', \@options, 
			undef, undef, \$current_option),
     option_popup => [ \&tag_option_popup, \$current_option ],
    );

  return $req->dyn_response('user/bookseminar', \%acts);
}

sub tag_option_popup {
  my ($roption) = @_;

  $$roption 
    or return '** popup_option not in options iterator **';

  my $option = $$roption;

  my $value = $option->{value} || $option->{values}[0];

  return popup_menu(-name => $option->{id},
		    -values => $option->{values},
		    -labels => $option->{labels},
		    -default => $value);
}

sub req_bookconfirm {
  my ($self, $req) = @_;

  my $cgi = $req->cgi;
  my $seminar_id = $cgi->param('id');
  defined $seminar_id && $seminar_id =~ /^\d+$/
    or return $self->error($req, "Seminar id parameter missing");

  require BSE::TB::Seminars;
  my $seminar = BSE::TB::Seminars->getByPkey($seminar_id)
    or return $self->error($req, "Unknown seminar");

  $seminar->{retailPrice} == 0
    or return $self->error($req, "This is only available for free seminars");

  my $session_id = $cgi->param('session_id');
  defined $session_id && $session_id =~ /^\d+$/
    or return $self->req_bookseminar($req, { session_id => "Please select a session" });

  require BSE::TB::SeminarSessions;
  my $session = BSE::TB::SeminarSessions->getByPkey($session_id)
    or return $self->req_bookseminar($req, { session_id => "Unknown session id" });

  # make sure the user isn't already booked for this
  $session->get_booking($req->siteuser)
    and return $self->req_bookseminar($req, { session_id => "You are already booked for this session"} );

  my @opt_names = split /,/, $seminar->{options};
  my @opt_values = map { ($cgi->param($_))[0] } @opt_names;
  my @options = $seminar->option_descs($req->cfg, \@opt_values);

  my $it = BSE::Util::Iterate->new;
  my $current_option;
  my %acts;
  %acts =
    (
     $req->dyn_user_tags(),
     seminar => [ \&tag_hash, $seminar ],
     session => [ \&tag_hash, $session ],
     location => [ \&tag_hash, $session->location ],
     $it->make_iterator(undef, 'option', 'options', \@options, 
			undef, undef, \$current_option),
    );

  return $req->dyn_response('user/bookconfirm', \%acts);
}

sub req_book {
  my ($self, $req) = @_;

  my $cgi = $req->cgi;
  my $cfg = $req->cfg;
  my $seminar_id = $cgi->param('id');
  defined $seminar_id && $seminar_id =~ /^\d+$/
    or return $self->error($req, "Seminar id parameter missing");

  require BSE::TB::Seminars;
  my $seminar = BSE::TB::Seminars->getByPkey($seminar_id)
    or return $self->error($req, "Unknown seminar");

  $seminar->{retailPrice} == 0
    or return $self->error($req, "This is only available for free seminars");

  my $session_id = $cgi->param('session_id');
  defined $session_id && $session_id =~ /^\d+$/
    or return $self->req_bookseminar($req, { session_id => "Please select a session" });

  require BSE::TB::SeminarSessions;
  my $session = BSE::TB::SeminarSessions->getByPkey($session_id)
    or return $self->req_bookseminar($req, { session_id => "Unknown session id" });

  # make sure the user isn't already booked for this
  require BSE::TB::SeminarBookings;
  $session->get_booking($req->siteuser)
    and return $self->req_bookseminar($req, { session_id => "You are already booked for this session"} );

  my @opt_names = split /,/, $seminar->{options};
  my @opt_values = map { ($cgi->param($_))[0] } @opt_names;

  my %more;
  for my $name (qw/customer_instructions support_notes roll_present/) {
    my $value = $cgi->param($name);
    $value and $more{$name} = $value;
  }
  $more{roll_present} = 0;
  $more{options}      = join(',', @opt_values);

  my $booking;
  eval {
    $booking = $session->add_attendee($req->siteuser, %more);
  };
  if ($@) {
    if ($@ =~ /duplicate/) {
      return $self->req_bookseminar($req, { session_id => "You appear to be already booked for this seminar" });
    }
    else {
      return $self->req_bookseminar($req, { _error => $@ });
    }
  }

  my $message;
  if ($cfg->entry('seminars', 'notify_user_booking', 1)) {
    my $email = $cfg->entry('seminar', 'notify_user_booking_email')
      || $cfg->entry('shop', 'from', $Constants::SHOP_FROM);
    my $from = $cfg->entry('shop', 'from', $Constants::SHOP_FROM);
    my $subject = $cfg->entry('seminar', 'notify_user_booking_subject',
			      'A user has booked a seminar session');
    my @sem_options = $seminar->option_descs($cfg, \@opt_values);
    my $it = DevHelp::Tags::Iterate->new;
    my %acts =
      (
       BSE::Util::Tags->static(undef, $cfg),
       user => [ \&tag_hash_plain, $req->siteuser ],
       seminar => [ \&tag_hash_plain, $seminar ],
       session => [ \&tag_hash_plain, $session ],
       location => [ \&tag_hash_plain, $session->location ],
       booking => [ \&tag_hash_plain, $booking ],
       $it->make_iterator(undef, 'option', 'options', \@sem_options),
      );
    require BSE::ComposeMail;
    my $mailer = BSE::ComposeMail->new(cfg => $cfg);
    unless ($mailer->send(to	   => $email,
			  from     => $from,
			  subject  => $subject,
			  template => 'admin/user_book_seminar',
			  acts	   => \%acts)) {
      $message = "Your seminar has been booked but there was an error sending an email notification to the system administrator:".$mailer->errstr;
    }
  }
  
  # refresh to the completion page
  my %params =
    (
     a_bookcomplete => 1,
     _p => $self->controller_id,
     id => $booking->{id},
    );
  $message and $params{m} = $message;
  my $url = $ENV{SCRIPT_NAME} . '?' .
    join '&', map { "$_=". escape_uri($params{$_}) } keys %params;

  return BSE::Template->get_refresh($url, $req->cfg);
}

sub req_bookcomplete {
  my ($self, $req) = @_;

  my $id = $req->cgi->param('id');
  defined $id || $id =~ /^\d+$/
    or return $self->error($req, "No booking id supplied");

  require BSE::TB::SeminarBookings;
  my $booking = BSE::TB::SeminarBookings->getByPkey($id);
  my $user = $req->siteuser;
  $booking && $booking->{siteuser_id} == $user->{id}
    or return $self->error($req, "No such booking found");

  my $session = $booking->session;
  my $seminar = $session->seminar;
  my @opt_values = split /,/, $booking->{options};
  my @options = $seminar->option_descs($req->cfg, \@opt_values);
  my %acts;
  my $message = $req->message();
  my $it = BSE::Util::Iterate->new;
  %acts =
    (
     $req->dyn_user_tags(),
     seminar => [ \&tag_hash, $seminar ],
     session => [ \&tag_hash, $session ],
     location => [ \&tag_hash, $session->location ],
     booking => [ \&tag_hash, $booking ],
     message => escape_html($message),
     $it->make_iterator(undef, 'option', 'options', \@options),
    );

  return $req->dyn_response('user/bookcomplete', \%acts);
}

sub check_action {
  my ($self, $req, $action, $rresult) = @_;

  unless ($req->siteuser) {
    my %logon_params;
    if ($ENV{REQUEST_METHOD} eq 'GET') {
      my @params =
	(
	 "a_$action" => 1,
	 _p => $self->controller_id,
	);
      my $cgi = $req->cgi;
      for my $name ($cgi->param) {
	my @values = $cgi->param($name);
	push @params, $name => $_ for @values;
      }
      my @param_args;
      while (@params) {
	my ($name, $value) = splice @params, 0, 2;
	push @param_args, $name . '=' . escape_uri($value);
      }
      my $r = $ENV{SCRIPT_NAME} . '?' . join '&', @param_args;
      $logon_params{r} = $r;
    }
    $logon_params{message} = 
      $req->text('needlogongen', "You need to logon to use this function");
    $logon_params{show_logon} = 1;
    my $logon = '/cgi-bin/user.pl?' . join '&',
      map { $_ . '=' . escape_uri($logon_params{$_}) } keys %logon_params;
    $$rresult = BSE::Template->get_refresh($logon, $req->cfg);
    return;
  }

  return 1;
}

1;
