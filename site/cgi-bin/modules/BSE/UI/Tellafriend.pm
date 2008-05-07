package BSE::UI::Tellafriend;
use strict;
use base 'BSE::UI::Dispatch';
use BSE::Util::Secure qw/make_secret/;
use BSE::Util::Tags qw(tag_hash tag_error_img tag_hash_plain tag_article tag_article_plain);
use BSE::ComposeMail;
use Articles;

my %actions =
  (
   form => 1,
   send => 1,
   done => 1,
  );

sub default_action {
  'form'
}

sub actions {
  \%actions;
}

sub _article {
  my ($self, $req, $error) = @_;

  my $id = $req->cgi->param('page');
  unless (defined $id and $id =~ /^\d+$/) {
    $$error = "page parameter missing";
    return;
  }

  my $article = Articles->getByPkey($id);
  unless ($article) {
    $$error = "article $id not found";
    return;
  }

  unless ($req->siteuser_has_access($article)) {
    $$error = "Sorry, you don't have access to that article";
    return;
  }

  return $article;
}

sub req_form {
  my ($self, $req, $errors) = @_;

  my $cgi = $req->cgi;
  unless ($req->session->{tellafriend}) {
    $req->session->{tellafriend} =
      {
       key => make_secret($req->cfg)
      };
  }

  my $error;
  my $article = $self->_article($req, \$error)
    or return $self->error($req, $error);

  my $message = $req->message($errors);

  my $siteuser = $req->siteuser;
  if ($siteuser) {
    # default from the user if they're logged in
    $cgi->param('from_email')
      or $cgi->param('from_email' => $siteuser->{email});
    $cgi->param('from_name')
      or $cgi->param('from_name' => "$siteuser->{name1} $siteuser->{name2}");
  }

  my %acts;
  %acts =
    (
     $req->dyn_user_tags,
     message => $message,
     tarticle => [ \&tag_article, $article, $req->cfg ],
     secret => $req->session->{tellafriend}{key},
     error_img => [ \&tag_error_img, $req->cfg, $errors ],
    );

  return $req->dyn_response('tellafriend/form', \%acts);
}

my %fields =
  (
   from_email =>
   {
    description => "From Email Address",
    rules => 'email;required',
    maxlength => 130,
   },
   from_name =>
   {
    description => "From Name",
    rules => 'dh_one_line;required',
    maxlength => 60,
   },
   to_email =>
   {
    description => "To Email Address",
    rules => 'email;required',
    maxlength => 130,
   },
   to_name =>
   {
    description => "To Name",
    rules => 'dh_one_line;required',
    maxlength => 60,
   },
   note =>
   {
    description => "Note",
    rules => 'dh_one_line',
    maxlength => 60,
   },
  );

sub req_send {
  my ($self, $req) = @_;

  my $cgi = $req->cgi;

  $req->session->{tellafriend}
    or return $self->req_form($req);

  my %errors;
  $req->validate(errors => \%errors,
		 fields => \%fields,
		 section => 'Tell a friend form');
  unless (keys %errors) {
    my $key = $cgi->param('key');
    $key
      or return $self->req_form($req);

    $key eq $req->session->{tellafriend}{key}
      or $errors{key} = 'Please resubmit from this form, your form key is incorrect';
  }

  delete $req->session->{tellafriend};

  keys %errors
    and return $self->req_form($req, \%errors);
 
  my $error;
  my $article = $self->_article($req, \$error)
    or return $self->error($req, $error);

  my $empty = $cgi->param('key2');
  if (defined $empty && $empty eq '') {
    my $to_email = $cgi->param('to_email');
    my $to_name = $cgi->param('to_name');
    my $from_email = $cgi->param('from_email');
    my $from_name = $cgi->param('from_name');
    my $link = $article->link($req->cfg);
    unless ($link =~ /^\w+:/) {
      $link = $req->cfg->entryErr('site', 'url') . $link;
    }
    my %acts;
    %acts =
      (
       BSE::Util::Tags->static(\%acts, $req->cfg),
       tarticle => [ \&tag_article_plain, $article, $req->cfg ],
       note => scalar $cgi->param('note'),
       from_name => $from_name,
       from_email => $from_email,
       to_name => $to_name,
       to_email => $to_email,
       sender_ip => $ENV{REMOTE_ADDR},
       link => $link,
      );
    my $subject = $req->cfg->entry('tellafriend', 'subject', "An interesting article");
    $subject =~ s/\{(\w+)\}/exists $article->{$1} ? $article->{$1} : "{$1}"/ge;
    my $mailer = BSE::ComposeMail->new(cfg => $req->cfg);
    $mailer->send(to => $to_email,
		  to_name => $to_name,
		  from => $from_email,
		  from_name => $from_name,
		  subject => $subject,
		  acts => \%acts,
		  template => 'tellafriend/email')
      or return $self->req_form($req, { _ => "Error sending email: " . $mailer->errstr });
  }
  
  my $url = $cgi->param('r');
  unless ($url) {
    $url = $req->user_url('tellafriend', 'done', page => $article->{id});
  }

  return BSE::Template->get_refresh($url, $req->cfg);
}

sub req_done {
  my ($self, $req) = @_;

  my $error;
  my $article = $self->_article($req, \$error)
    or return $self->error($req, $error);

  my %acts;
  %acts =
    (
     $req->dyn_user_tags,
     tarticle => [ \&tag_article, $article, $req->cfg ],
    );

  return $req->dyn_response('tellafriend/done', \%acts);
}

1;
