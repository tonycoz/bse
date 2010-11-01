package BSE::TB::AuditEntry;
use strict;
use base qw(Squirrel::Row);

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

1;
