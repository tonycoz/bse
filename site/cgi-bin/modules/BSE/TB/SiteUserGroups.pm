package BSE::TB::SiteUserGroups;
use strict;
use base 'Squirrel::Table';
use BSE::TB::SiteUserGroup;

use constant SECT_QUERY_GROUPS => "Query Groups";
use constant SECT_QUERY_GROUP_PREFIX => 'Query group ';

sub rowClass { 'BSE::TB::SiteUserGroup' }

sub query_groups {
  my ($class, $cfg) = @_;

  my @groups;
  my $id = 1;
  my $name;
  while ($name = $cfg->entry(SECT_QUERY_GROUPS, $id)) {
    my $group = $class->getQueryGroup($cfg, -$id);
    $group and push @groups, $group;
      
    ++$id;
  }

  return @groups;
}

sub admin_and_query_groups {
  my ($class, $cfg) = @_;

  return
    (
     $class->all,
     $class->query_groups($cfg),
    );
}

sub getQueryGroup {
  my ($class, $cfg, $id) = @_;

  my $name = $cfg->entry(SECT_QUERY_GROUPS, -$id)
    or return;
  my $sql = $cfg->entry(SECT_QUERY_GROUP_PREFIX.$name, 'sql')
    or return;

  return bless { id => $id, name => "*$name", sql=>$sql }, 
    "BSE::TB::SiteUserQueryGroup";
}

sub getByName {
  my ($class, $cfg, $name) = @_;

  if ($name =~ /^\*/) {
    $name = substr($name, 1);

    my %q_groups = map lc, reverse $cfg->entries(SECT_QUERY_GROUPS);
    if ($q_groups{lc $name}) {
      return $class->getQueryGroup($cfg, -$q_groups{lc $name})
	or return;
    }
    else {
      return;
    }
  }
  else {
    return $class->getBy(name => $name);
  }
}

package BSE::TB::SiteUserQueryGroup;
use constant OWNER_TYPE => "G";

sub id { $_[0]{id} }

sub name { $_[0]{name} }

sub contains_user {
  my ($self, $user) = @_;

  my $id = ref $user ? $user->{id} : $user;

  my $rows = BSE::DB->single->dbh->selectall_arrayref($self->{sql}, { MaxRows=>1 }, $id);
  $rows && @$rows
    and return 1;
  
  return 0;
}

sub file_owner_type {
  return OWNER_TYPE;
}

sub files {
  my ($self) = @_;

  require BSE::TB::OwnedFiles;
  return BSE::TB::OwnedFiles->getBy(owner_type => OWNER_TYPE,
				    owner_id => $self->id);
}

sub data_only {
  return +{ %{$_[0]} };
}

1;
