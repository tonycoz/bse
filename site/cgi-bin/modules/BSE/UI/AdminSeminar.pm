package BSE::UI::AdminSeminar;
use strict;
use base qw(BSE::UI::AdminDispatch);
use BSE::Util::Tags qw(tag_hash tag_error_img);
use BSE::Util::DynSort qw(sorter tag_sorthelp);
use BSE::Template;
use BSE::Util::Iterate;
use BSE::TB::Locations;
use DevHelp::HTML;
use constant SECT_LOCATION_VALIDATION => "BSE Location Validation";

my %rights =
  (
   loclist => 'bse_location_list',
   locaddform => 'bse_location_add',
   locadd => 'bse_location_add',
   locedit => 'bse_location_edit',
   locsave => 'bse_location_edit',
   locdelask => 'bse_location_delete',
   locdelete => 'bse_location_delete',
#    detail => 'bse_subscr_detail',
#    update => 'bse_subscr_update',
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
     BSE::Util::Tags->basic(\%acts, $req->cgi, $req->cfg),
     BSE::Util::Tags->admin(\%acts, $req->cfg),
     BSE::Util::Tags->secure($req),
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
  $req->configure_fields(\%fields, SECT_LOCATION_VALIDATION);

  my %acts;
  %acts =
    (
     BSE::Util::Tags->basic(\%acts, $req->cgi, $req->cfg),
     BSE::Util::Tags->admin(\%acts, $req->cfg),
     BSE::Util::Tags->secure($req),
     msg => $msg,
     message => $msg,
     error_img => [ \&tag_error_img, $req->cfg, $errors ],
     field => [ \&tag_field, \%fields ],
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
  $req->configure_fields(\%fields, SECT_LOCATION_VALIDATION);

  my %acts;
  %acts =
    (
     BSE::Util::Tags->basic(\%acts, $req->cgi, $req->cfg),
     BSE::Util::Tags->admin(\%acts, $req->cfg),
     BSE::Util::Tags->secure($req),
     msg => $msg,
     message => $msg,
     error_img => [ \&tag_error_img, $req->cfg, $errors ],
     location => [ \&tag_hash, $location ],
     field => [ \&tag_field, \%fields ],
    );

  return $req->dyn_response($template, \%acts);
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

1;
