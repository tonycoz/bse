package BSE::TB::AuditEntry;
use strict;
use base qw(Squirrel::Row);

our $VERSION = "1.004";

sub columns {
  return qw/id 
            when_at
	    facility
	    component
	    module
	    function
	    level
	    actor_type
	    actor_id
	    object_type
	    object_id
	    ip_address
	    msg
	    dump
	   /;
}

sub table {
  "bse_audit_log";
}

sub level_name {
  my ($self) = @_;

  return BSE::TB::AuditLog->level_id_to_name($self->level);
}

sub actor_name {
  my ($self) = @_;

  my $type = $self->actor_type;
  if ($type eq "U") {
    return "Unknown";
  }
  elsif ($type eq "E") {
    return "Error";
  }
  elsif ($type eq "S") {
    return "System";
  }
  elsif ($type eq "A") {
    require BSE::TB::AdminUsers;
    my $admin = BSE::TB::AdminUsers->getByPkey($self->actor_id);
    if ($admin) {
      return "Admin: ".$admin->logon;
    }
    else {
      return "Admin: " . $self->actor_id. " (not found)";
    }
  }
  elsif ($type eq "M") {
    require SiteUsers;
    my $user = SiteUsers->getByPkey($self->actor_id);
    if ($user) {
      return "Member: ".$user->userId;
    }
    else {
      return "Member: ".$self->actor_id . " (not found)";
    }
  }
  else {
    return "Unknown type $type";
  }
}

sub actor_link {
  my ($self) = @_;

  my $type = $self->actor_type;
  if ($type eq "A") {
    require BSE::TB::AdminUsers;
    my $admin = BSE::TB::AdminUsers->getByPkey($self->actor_id);
    if ($admin) {
      return $admin->link;
    }
    else {
      return "";
    }
  }
  elsif ($type eq "M") {
    require SiteUsers;
    my $user = SiteUsers->getByPkey($self->actor_id);
    if ($user) {
      return $user->link;
    }
    else {
      return "";
    }
  }
  else {
    return "";
  }
}

my %types =
  (
   "BSE::TB::Order" =>
   {
    target => "shopadmin",
    action => "order_detail",
    format => "Order %d",
   },
   "SiteUser" =>
   {
    target => "siteusers",
    action => "a_view",
    format => "Member %d",
    class => "SiteUsers",
   },
   "BSE::TB::AdminUser" =>
   {
    target => "adminusers",
    action => "a_showuser",
    format => "Admin: %d",
    class => "BSE::TB::AdminUsers",
   },
  );

sub object_link {
  my ($self) = @_;

  my $id = $self->object_id or return "";
  my $type = $self->object_type;
  my $entry = $types{$type};
  if ($entry) {
    BSE::Cfg->single->admin_url($entry->{target},
				{ id => $self->object_id,
				  $entry->{action} => 1 });
  }
  else {
    return "";
  }
}

sub object_name {
  my ($self) = @_;

  my $type = $self->object_type
    or return '(None)';
  my $entry = $types{$type};
  if ($entry->{class}) {
    if (eval "use $entry->{class}; 1"
       && (my $obj = $entry->{class}->getByPkey($self->object_id))) {
      return $obj->describe;
    }
  }
  if ($entry) {
    return sprintf $entry->{format}, $self->object_id;
  }
  elsif ($type) {
    return $type . ": " . $self->object_id;
  }
  else {
    return '(None)';
  }
}

1;
