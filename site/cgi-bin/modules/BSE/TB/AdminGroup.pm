package BSE::TB::AdminGroup;
use strict;
use base qw(BSE::TB::AdminBase);

sub columns {
  return ($_[0]->SUPER::columns,
	  qw/base_id name description perm_map/ );
}

sub bases {
  return { base_id=>{ class=>'BSE::TB::AdminBase' } };
}

sub remove {
  my ($self) = @_;

  BSE::DB->run(deleteGroupUsers => $self->{id});

  $self->SUPER::remove();
}

1;
