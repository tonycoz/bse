package BSE::TB::SiteUserGroups;
use strict;
use base 'Squirrel::Table';
use BSE::TB::SiteUserGroup;

use constant SECT_QUERY_GROUPS => "Query Groups";
use constant SECT_QUERY_GROUP_PREFIX => 'Query group ';

sub rowClass { 'BSE::TB::SiteUserGroup' }

sub admin_and_query_groups {
  my ($class, $cfg) = @_;

  my @groups = $class->all;

  my $id = 1;
  my $name;
  while ($name = $cfg->entry(SECT_QUERY_GROUPS, $id)) {
    my $group = $class->getQueryGroup($cfg, -$id);
    $group and push @groups, $group;
      
    ++$id;
  }

  @groups;
}

sub getQueryGroup {
  my ($class, $cfg, $id) = @_;

  my $name = $cfg->entry(SECT_QUERY_GROUPS, -$id)
    or return;
  my $sql = $cfg->entry(SECT_QUERY_GROUP_PREFIX.$name, 'sql')
    or return;

  return { id => $id, name => $name, sql=>$sql };
}

1;
