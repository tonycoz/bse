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

1;
