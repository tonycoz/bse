package BSE::UI::SubAdmin;
use strict;
use base qw(BSE::UI::AdminDispatch);
use BSE::Util::Tags qw(tag_hash tag_error_img);
use BSE::Util::DynSort qw(sorter tag_sorthelp);
use DevHelp::Validate qw(dh_validate);
use BSE::Template;
use BSE::Util::Iterate;
use BSE::TB::Subscriptions;
use DevHelp::HTML;

my %rights =
  (
   list => 'bse_subs_list',
   addform => 'bse_subs_add',
   add => 'bse_subs_add',
   edit => 'bse_subs_edit',
   save => 'bse_subs_edit',
   detail => 'bse_subs_detail',
  );

sub actions { \%rights }

sub rights { \%rights }

sub default_action { 'list' }

sub req_list {
  my ($class, $req, $errors) = @_;

  my $msg = $req->message($errors);
  my $cgi = $req->cgi;
  my @subs = BSE::TB::Subscriptions->all;
  my ($sortby, $reverse) =
    sorter(data=>\@subs, cgi=>$cgi, sortby=>'subscription_id', 
	   session=>$req->session,
           name=>'subs', fields=> { subscription_id => {numeric => 1 },
				     max_lapsed => { numeric => 1}});
  my $it = BSE::Util::Iterate->new;

  my %acts;
  %acts =
    (
     BSE::Util::Tags->basic(\%acts, $req->cgi, $req->cfg),
     BSE::Util::Tags->admin(\%acts, $req->cfg),
     BSE::Util::Tags->secure($req),
     msg => $msg,
     message => $msg,
     $it->make_paged_iterator('isubscription', 'subscriptions', \@subs, undef,
                              $cgi, undef, 'pp=20', $req->session, 
                              'subscriptions'),
     sorthelp => [ \&tag_sorthelp, $sortby, $reverse ],
     sortby=>$sortby,
     reverse=>$reverse,
    );

  return $req->dyn_response('admin/subscr/list', \%acts);
}

sub req_addform {
  my ($class, $req, $errors) = @_;

  my $msg = $req->message($errors);

  my %acts;
  %acts =
    (
     BSE::Util::Tags->basic(\%acts, $req->cgi, $req->cfg),
     BSE::Util::Tags->admin(\%acts, $req->cfg),
     BSE::Util::Tags->secure($req),
     msg => $msg,
     message => $msg,
     error_img => [ \&tag_error_img, $req->cfg, $errors ],
    );

  return $req->dyn_response('admin/subscr/add', \%acts);
}

sub req_add {
  my ($class, $req) = @_;

  my $cgi = $req->cgi;
  my $cfg = $req->cfg;
  my %fields = BSE::TB::Subscription->valid_fields($cfg);
  my %rules = BSE::TB::Subscription->valid_rules($cfg);
  my %errors;
  dh_validate($cgi, \%errors, 
	      { fields => \%fields, rules=> \%rules },
	      $cfg, "BSE Subscription Validation");

  keys %errors
    and return $class->req_addform($req, \%errors);

  my %sub;
  for my $field (keys %fields) {
    $sub{$field} = $cgi->param($field);
  }
  my @cols = BSE::TB::Subscription->columns;
  shift @cols;
  my $sub = BSE::TB::Subscriptions->add(@sub{@cols});

  my $r = $class->_list_refresh($req, "Subscription $sub{text_id} added");

  return BSE::Template->get_refresh($r, $req->cfg);
}

sub req_edit {
  my ($class, $req, $errors) = @_;

  my $sub_id = $req->cgi->param('subscription_id');
  $sub_id && $sub_id =~ /^\d+/
    or return $class->req_list
      ($req, { subscription_id=>'Missing or invalid subscription_id' });
  my $sub = BSE::TB::Subscriptions->getByPkey($sub_id);
  $sub
    or return $class->req_list
      ($req, { subscription_id=>'Unknown subscription_id' });

  my $msg = $req->message($errors);

  my %acts;
  %acts =
    (
     BSE::Util::Tags->basic(\%acts, $req->cgi, $req->cfg),
     BSE::Util::Tags->admin(\%acts, $req->cfg),
     BSE::Util::Tags->secure($req),
     msg => $msg,
     message => $msg,
     error_img => [ \&tag_error_img, $req->cfg, $errors ],
     subscription => [ \&tag_hash, $sub ],
    );

  return $req->dyn_response('admin/subscr/edit', \%acts);
}

sub req_save {
  my ($class, $req) = @_;

  my $sub_id = $req->cgi->param('subscription_id');
  $sub_id && $sub_id =~ /^\d+/
    or return $class->req_list
      ($req, { subscription_id=>'Missing or invalid subscription_id' });
  my $sub = BSE::TB::Subscriptions->getByPkey($sub_id);
  $sub
    or return $class->req_list
      ($req, { subscription_id=>'Unknown subscription_id' });

  my $cgi = $req->cgi;
  my $cfg = $req->cfg;
  my %fields = $sub->valid_fields($cfg);
  my %rules = $sub->valid_rules($cfg);
  my %errors;
  dh_validate($cgi, \%errors, 
	      { fields => \%fields, rules=> \%rules },
	      $cfg, "BSE Subscription Validation");

  keys %errors
    and return $class->req_edit($req, \%errors);

  for my $field (keys %fields) {
    $sub->{$field} = $cgi->param($field);
  }

  $sub->save;

  my $r = $class->_list_refresh($req, "Subscription $sub->{text_id} saved");

  return BSE::Template->get_refresh($r, $req->cfg);
}

sub req_detail {
  my ($class, $req) = @_;

  my $sub_id = $req->cgi->param('subscription_id');
  $sub_id && $sub_id =~ /^\d+/
    or return $class->req_list
      ($req, { subscription_id=>'Missing or invalid subscription_id' });
  my $sub = BSE::TB::Subscriptions->getByPkey($sub_id);
  $sub
    or return $class->req_list
      ($req, { subscription_id=>'Unknown subscription_id' });

  my $msg = $req->message($errors);

  my %acts;
  %acts =
    (
     BSE::Util::Tags->basic(\%acts, $req->cgi, $req->cfg),
     BSE::Util::Tags->admin(\%acts, $req->cfg),
     BSE::Util::Tags->secure($req),
     msg => $msg,
     message => $msg,
     subscription => [ \&tag_hash, $sub ],
     # products that use it
     # users subscribed to it
    );

  return $req->dyn_response('admin/subscr/detail', \%acts);
}

sub _list_refresh {
  my ($class, $req, $msg) = @_;

  my $r = $req->cgi->param('r') || $req->cgi->param('refreshto');
  unless ($r) {
    $r = "/cgi-bin/admin/subadmin.pl";
  }
  if ($msg) {
    my $sep = $r =~ /\?/ ? '&' : '?';

    $r .= $sep . escape_uri($msg);
  }

  return $r;
}

1;
