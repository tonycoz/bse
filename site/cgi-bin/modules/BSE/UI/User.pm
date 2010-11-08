package BSE::UI::User;
use strict;
use base 'BSE::UI::Dispatch';
use BSE::Util::Tags qw(tag_hash tag_error_img tag_hash_plain);
use BSE::Util::HTML qw(:default popup_menu);
use BSE::Util::Iterate;
use BSE::Util::SQL qw/now_datetime/;
use DevHelp::Date qw(dh_strftime_sql_datetime);
use base 'BSE::UI::UserCommon';

our $VERSION = "1.000";

my %actions =
  (
   info => 1,
   bookseminar => 1,
   bookconfirm => 1,
   book => 1,
   bookcomplete => 1,
   bookinglist => 1,
   bookingdetail => 1,
   cancelbookingconfirm => 1,
   cancelbooking => 1,
   editbooking => 1,
   savebooking => 1,
   wishlistadd => 1,
   wishlistdel => 1,
   wishlistup => 1,
   wishlistdown => 1,
   wishlisttop => 1,
   wishlistbottom => 1,
   wishlist => 1,
  );

sub default_action {
  'info';
}

sub actions {
  \%actions;
}

sub req_info {
  my ($self, $req) = @_;

  my $user = $req->siteuser;

  my $cfg = $req->cfg;
  my $cgi = $req->cgi;

  require BSE::TB::Orders;
  my @orders = sort { $b->{orderDate} cmp $a->{orderDate}
			|| $b->{id} <=> $a->{id} }
    BSE::TB::Orders->getBy(userId=>$user->{userId});

  my $must_be_paid = $cfg->entryBool('downloads', 'must_be_paid', 0);
  my $must_be_filled = $cfg->entryBool('downloads', 'must_be_filled', 0);

  my $it = BSE::Util::Iterate->new;
  my $order_index;
  my $item_index;
  my @items;
  my %acts;
  my $product;
  my @files;
  my $file_index;
  my $message = $req->message();
  %acts =
    (
     $req->dyn_user_tags,
     message => $message,
     BSE::Util::Tags->make_iterator(\@orders, 'order', 'orders', 
				    \$order_index),
     BSE::Util::Tags->
     make_dependent_iterator(\$order_index,
			     sub {
			       require BSE::TB::OrderItems;
			       @items = BSE::TB::OrderItems->
				 getBy(orderId=>$orders[$_[0]]{id});
			     },
			     'item', 'items', \$item_index),
     BSE::Util::Tags->
     make_dependent_iterator(\$order_index,
			     sub {
			       @files = BSE::DB->query
				 (orderFiles=>$orders[$_[0]]{id});
			     },
			     'orderfile', 'orderfiles', \$file_index),
     product =>
     sub {
       require Products;
       $product = Products->getByPkey($items[$item_index]{productId})
	 unless $product && $product->{id} == $items[$item_index]{productId};
       return tag_article($product, $cfg, $_[0]);
     },
     BSE::Util::Tags->
     make_multidependent_iterator
     ([ \$item_index, \$order_index],
      sub {
	require 'ArticleFiles.pm';
	@files = sort { $b->{displayOrder} <=> $a->{displayOrder} }
	  BSE::TB::ArticleFiles->getBy(articleId=>$items[$item_index]{productId});
      },
      'prodfile', 'prodfiles', \$file_index),
     ifFileAvail =>
     sub {
       if ($file_index >= 0 && $file_index < @files) {
	 return 1 if !$files[$file_index]{forSale};
       }
       return 0 if $must_be_paid && !$orders[$order_index]{paidFor};
       return 0 if $must_be_filled && !$orders[$order_index]{filled};
       return 1;
     },
     options => [ tag_order_item_options => $self, $req, \$item_index, \@items ],
     $it->make_iterator([ \&iter_usersubs, $user ], 
			'subscription', 'subscriptions'),
     $it->make_iterator([ \&iter_sembookings, $user ],
			'booking', 'bookings'),
    );

  return $req->dyn_response('user/userpage', \%acts);
}

sub iter_usersubs {
  my ($user) = @_;

  $user->subscribed_services;
}

sub iter_sembookings {
  my ($user) = @_;

  $user->seminar_bookings_detail;
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
     option_popup => [ \&tag_option_popup, $cgi, \$current_option ],
    );

  return $req->dyn_response('user/bookseminar', \%acts);
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
  my $message ||= $req->message();
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

sub req_bookinglist {
  my ($class, $req, $message) = @_;

  my @bookings = $req->siteuser->seminar_bookings_detail;
  my $now = now_datetime;
  for my $booking (@bookings) {
    $booking->{past} = $booking->{when_at} lt $now ? 1 : 0;
  }
  my $show_past = $req->cgi->param('show_past');
  unless ($show_past) {
    @bookings = grep !$_->{past}, @bookings;
  }

  $message ||= $req->message;

  my $it = BSE::Util::Iterate->new;
  my %acts;
  %acts =
    (
     $req->dyn_user_tags(),
     $it->make_iterator(undef, 'booking', 'bookings', \@bookings),
     message => escape_html($message),
    );

  return $req->dyn_response('user/bookinglist', \%acts);
}

sub _show_booking {
  my ($class, $req, $template, $errors) = @_;

  my $cgi = $req->cgi;

  my $id = $cgi->param('id');
  defined $id && $id =~ /^\d+$/
    or return $class->req_bookinglist($req, "id parameter invalid");

  require BSE::TB::SeminarBookings;
  my $booking = BSE::TB::SeminarBookings->getByPkey($id);
  $booking && $booking->{siteuser_id} == $req->siteuser->{id}
    or return $class->req_bookinglist($req, "booking $id not found");

  my $session = $booking->session;

  my $seminar = $session->seminar;
  my @sem_options = 
    $seminar->option_descs($req->cfg, [ split /,/, $booking->{options} ]);

  my $message = $req->message($errors);
  $message = escape_html($message);

  my $it = BSE::Util::Iterate->new;
  my %acts;
  %acts =
    (
     $req->dyn_user_tags(),
     session  => [ \&tag_hash, $session  ],
     seminar  => [ \&tag_hash, $seminar ],
     location => [ \&tag_hash, $session->location ],
     booking  => [ \&tag_hash, $booking  ],
     message  => $message,
     $it->make_iterator(undef, 'option', 'options', \@sem_options),
    );

  return $req->dyn_response($template, \%acts);
}

sub req_bookingdetail {
  my ($class, $req) = @_;

  return $class->_show_booking($req, 'user/bookingdetail');
}

sub req_cancelbookingconfirm {
  my ($class, $req, $message) = @_;

  return $class->_show_booking($req, 'user/cancelbooking', $message);
}

sub req_cancelbooking {
  my ($class, $req) = @_;

  my $cgi = $req->cgi;

  my $id = $cgi->param('id');
  defined $id && $id =~ /^\d+$/
    or return $class->req_bookinglist($req, "id parameter invalid");

  my $siteuser = $req->siteuser;

  require BSE::TB::SeminarBookings;
  my $booking = BSE::TB::SeminarBookings->getByPkey($id);
  $booking && $booking->{siteuser_id} == $siteuser->{id}
    or return $class->req_bookinglist($req, "booking $id not found");

  my $session = $booking->session;

  $session->{when_at} gt now_datetime
    or return $class->req_bookinglist($req, "You cannot modify past bookings");

  my @options = split /,/, $booking->{options};
  local $SIG{__DIE__};
  eval {
    $session->remove_booking($siteuser);
  };
  $@ and return $class->req_cancelbookingconfirm
    ($req, "Could not remove booking $@");

  my $seminar = $session->seminar;

  my @sem_options = $seminar->option_descs($req->cfg, \@options);

  require BSE::ComposeMail;
  my $cfg = $req->cfg;
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

  my $mailer = BSE::ComposeMail->new(cfg => $cfg);
  if ($cfg->entry('seminars', 'notify_user_cancel', 1)) {
    my $email = $cfg->entry('seminar', 'notify_user_cancel_email')
      || $cfg->entry('shop', 'from', $Constants::SHOP_FROM);
    my $from = $cfg->entry('shop', 'from', $Constants::SHOP_FROM);
    my $subject = $cfg->entry('seminar', 'notify_user_cancel_subject',
			      'A user has cancelled their booking');
    unless ($mailer->send(to        => $email,
			  subject   => $subject,
			  template  => 'admin/user_unbook_seminar',
			  acts      => \%acts)) {
      return $class->req_cancelbookingconfirm
	($req, "The user booking was cancelled, but there was an error sending the email notification:".$mailer->errstr );
    }
  }
  my $subject = $cfg->entry('seminars', 'unbooked_notify_subject',
			    'Seminar booking cancellation confirmation');
  unless ($mailer->send(to	  => $siteuser,
			subject	  => $subject,
			template  => 'user/email_unbook_seminar',
			acts	  => \%acts)) {
    return $class->req_cancelbookingconfirm
      ($req, "The user booking was cancelled, but there was an error sending the email notification:".$mailer->errstr );
  }

  my $r = $cgi->param('r');
  unless ($r) {
    $r = '/cgi-bin/nuser.pl/user/bookinglist';
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
    or return $class->req_bookinglist($req, "id parameter invalid");

  my $siteuser = $req->siteuser;

  require BSE::TB::SeminarBookings;
  my $booking = BSE::TB::SeminarBookings->getByPkey($id);

  $booking && $booking->{siteuser_id} == $siteuser->{id}
    or return $class->req_bookinglist($req, "booking $id not found");

  my $session = $booking->session;

  my $now = now_datetime;
  $session->{when_at} gt $now
    or return $class->req_bookinglist($req, "You cannot modify past bookings");

  my $message = $req->message($errors);

  my $seminar = $session->seminar;
  my @sem_options = 
    $seminar->option_descs($req->cfg, [ split /,/,  $booking->{options} ]);
  my @unbooked = $seminar->get_unbooked_by_user($siteuser);
  @unbooked = 
    sort { $b->{when_at} cmp $a->{when_at} } 
      grep $_->{when_at} gt $now, ( @unbooked, $session );
    
  my $current_option;
  my $it = BSE::Util::Iterate->new;
  my %acts;
  %acts =
    (
     $req->dyn_user_tags(),
     session  => [ \&tag_hash, $session  ],
     seminar  => [ \&tag_hash, $seminar ],
     location => [ \&tag_hash, $session->location ],
     booking  => [ \&tag_hash, $booking  ],
     message  => escape_html($message),
     error_img => [ \&tag_error_img, $req->cfg, $errors ],
     $it->make_iterator(undef, 'option', 'options', \@sem_options, 
			undef, undef, \$current_option),
     option_popup => [ \&tag_option_popup, $req->cgi, \$current_option ],
     $it->make_iterator(undef, 'isession', 'sessions', \@unbooked),
     session_popup => 
     [ \&tag_session_popup, $req->cfg, $booking, $req->cgi, \@unbooked ],
    );

  return $req->dyn_response('user/editbooking', \%acts);
}

sub req_savebooking {
  my ($self, $req, $message) = @_;

  my $cgi = $req->cgi;

  my $id = $cgi->param('id');
  defined $id && $id =~ /^\d+$/
    or return $self->req_bookinglist($req, "id parameter invalid");

  my $siteuser = $req->siteuser;

  require BSE::TB::SeminarBookings;
  my $booking = BSE::TB::SeminarBookings->getByPkey($id);
  $booking && $booking->{siteuser_id} == $siteuser->{id}
    or return $self->req_bookinglist($req, "booking $id not found");

  my $old_session = $booking->session;
  $old_session->{when_at} gt now_datetime
    or return $self->req_bookinglist($req, "You cannot modify past bookings");

  my @cols = qw/customer_instructions/;
  for my $name (@cols) {
    my $value = $cgi->param($name);
    defined $value and $booking->set($name => $value);
  }
  my %errors;
  my $session_id = $cgi->param('session_id');
  if (defined $session_id && $session_id != $booking->{session_id}) {
    my $new_session = BSE::TB::SeminarSessions->getByPkey($session_id);
    if ($old_session->{seminar_id} != $new_session->{seminar_id}) {
      $errors{session_id} = "Invalid session";
    }
    elsif ($new_session->{when_at} lt now_datetime) {
      $errors{session_id} = "That session is now in the past, sorry";
    }
    else {
      $booking->{session_id} = $new_session->{id};
    }
  }
  keys %errors
    and return $self->req_editbooking($req, \%errors);

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
    and return $self->req_editbooking($req, { error => $@ });

  my @sem_options = $seminar->option_descs($req->cfg, \@options);

  my $session = $booking->session;
  require BSE::ComposeMail;
  my $cfg = $req->cfg;
  my $mailer = BSE::ComposeMail->new(cfg => $cfg);
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

  if ($cfg->entry('seminars', 'notify_user_edit', 1)) {
    my $email = $cfg->entry('seminar', 'notify_user_edit_email')
      || $cfg->entry('shop', 'from', $Constants::SHOP_FROM);
    my $subject = $cfg->entry('seminar', 'notify_user_edit_subject',
			      'A user has edited their booking');
    unless ($mailer->send(to        => $email,
			  subject   => $subject,
			  template  => 'admin/user_edit_seminar',
			  acts      => \%acts)) {
      return $self->req_editbooking
	($req, "Your booking was changed, but there was an error sending the email notification:".$mailer->errstr );
    }
  }

  my $subject = $cfg->entry('seminars', 'edit_notify_subject',
			    'Your seminar booking has been changed');
  unless ($mailer->send(to	  => $siteuser,
			subject	  => $subject,
			template  => 'user/email_edit_seminar',
			acts	  => \%acts)) {
    return $self->req_editbooking
      ($req, _email => "Your booking was changed, but there was an error sending the email notification:".$mailer->errstr );
  }

  my $r = $cgi->param('r');
  unless ($r) {
    $r = '/cgi-bin/nuser.pl/user/bookinglist'
  }
  $r .= $r =~ /\?/ ? '&' : '?';
  $r .= "m=Booking+updated";

  return BSE::Template->get_refresh($r, $req->cfg);
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

  $location->{description} . ' ' . 
    dh_strftime_sql_datetime($date_fmt, $session->{when_at});
}

sub _refresh_wishlist {
  my ($self, $req, $msg) = @_;

  my $url = $req->cgi->param('r');
  print STDERR "url $url\n" if $url;
  unless ($url) {
    $url = $req->user_url(nuser => userpage => _t => 'wishlist');
  }

  if ($url eq 'ajaxwishlist') {
    return $self->req_info($req, $msg);
  }
  else {
    $req->flash($msg);
    return BSE::Template->get_refresh($url, $req->cfg);
  }
}

sub _wishlist_product {
  my ($self, $req, $rresult) = @_;

  my $product_id = $req->cgi->param('product_id');
  unless (defined $product_id && $product_id =~ /^\d+$/) {
    $$rresult = $self->req_userpage($req, "Missing or invalid product id");
    return;
  }
  require Products;
  my $product = Products->getByPkey($product_id);
  unless ($product) {
    $$rresult = $self->req_userpage($req, "Unknown product id");
    return;
  }

  return $product;
}

sub req_wishlistadd {
  my ($self, $req) = @_;

  my $user = $req->siteuser;

  my $result;
  my $product = $self->_wishlist_product($req, \$result)
    or return $result;
  if ($user->product_in_wishlist($product)) {
    return $self->_refresh_wishlist($req, "Product $product->{title} is already in your wishlist");
  }

  eval {
    local $SIG{__DIE__};
    $user->add_to_wishlist($product);
  };
  $@
    and return $self->_refresh_wishlist($req, $@);

  return $self->_refresh_wishlist($req, "Product $product->{title} added to your wishlist");
}

sub req_wishlistdel {
  my ($self, $req) = @_;

  my $user = $req->siteuser;

  my $result;
  my $product = $self->_wishlist_product($req, \$result)
    or return $result;

  unless ($user->product_in_wishlist($product)) {
    return $self->_refresh_wishlist($req, "Product $product->{title} is not in your wishlist");
  }

  eval {
    local $SIG{__DIE__};
    $user->remove_from_wishlist($product);
  };
  $@
    and return $self->_refresh_wishlist($req, $@);

  return $self->_refresh_wishlist($req, "Product $product->{title} removed from your wishlist");
}

sub _wishlist_move {
  my ($self, $req, $method) = @_;

  my $user = $req->siteuser;

  my $result;
  my $product = $self->_wishlist_product($req, \$result)
    or return $result;

  unless ($user->product_in_wishlist($product)) {
    return $self->_refresh_wishlist($req, "Product $product->{title} is not in your wishlist");
  }

  eval {
    local $SIG{__DIE__};
    $user->$method($product);
  };
  $@
    and return $self->_refresh_wishlist($req, $@);

  return $self->_refresh_wishlist($req);
}

sub req_wishlisttop {
  my ($self, $req) = @_;

  return $self->_wishlist_move($req, 'move_to_wishlist_top');
}

sub req_wishlistbottom {
  my ($self, $req) = @_;

  return $self->_wishlist_move($req, 'move_to_wishlist_bottom');
}

sub req_wishlistup {
  my ($self, $req) = @_;

  return $self->_wishlist_move($req, 'move_up_wishlist');
}

sub req_wishlistdown {
  my ($self, $req) = @_;

  return $self->_wishlist_move($req, 'move_down_wishlist');
}

1;
