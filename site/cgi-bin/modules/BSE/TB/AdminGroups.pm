package BSE::TB::AdminGroups;
use strict;
use base 'Squirrel::Table';
use BSE::TB::AdminGroup;
use constant SECT_TEMPLATE_SETS => 'admin group template sets';

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

1;
