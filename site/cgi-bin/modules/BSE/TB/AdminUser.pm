package BSE::TB::AdminUser;
use strict;
use base qw(BSE::TB::AdminBase);

sub columns {
  return ($_[0]->SUPER::columns,
	  qw/base_id logon name password perm_map/);
}

sub bases {
  return { base_id=>{ class=>'BSE::TB::AdminBase' } };
}

1;
