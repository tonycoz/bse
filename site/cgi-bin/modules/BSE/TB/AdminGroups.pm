package BSE::TB::AdminGroups;
use strict;
use base 'Squirrel::Table';
use BSE::TB::AdminGroup;
use constant SECT_TEMPLATE_SETS => 'admin group template sets';

our $VERSION = "1.001";

sub rowClass {
  return 'BSE::TB::AdminGroup';
}

sub group_template_set_values {
  my ($class, $cfg) = @_;

  my %entries = $cfg->entries(SECT_TEMPLATE_SETS);
  return 
    ( 
     "",
     sort keys %entries,
    );
}

sub group_template_set_labels {
  my ($class, $req) = @_;

  
  my %entries = $req->cfg->entries(SECT_TEMPLATE_SETS);
  return 
    ( 
     "" => $req->text(bse_group_no_template_set => "(none)"),
     %entries,
    );
}

# group membership given a group id
sub group_members {
  my ($self, $id) = @_;

  require BSE::TB::AdminUsers;
  return BSE::TB::AdminUsers->getSpecial(group_members => $id);
}

1;
