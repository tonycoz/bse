package BSE::TB::SiteUserGroups;
use strict;
use base 'Squirrel::Table';
use BSE::TB::SiteUserGroup;

our $VERSION = "1.002";

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
  my $section = SECT_QUERY_GROUP_PREFIX . $name;
  my $sql = $cfg->entry($section, 'sql')
    or return;
  my $sql_all = $cfg->entry($section, 'sql_all');

  return bless
    {
     id => $id,
     name => "*$name",
     sql=>$sql,
     sql_all => $sql_all,
    }, "BSE::TB::SiteUserQueryGroup";
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

sub getById {
  my ($self, $id) = @_;

  return $id > 0 ? $self->getByPkey($id) : $self->getQueryGroup(BSE::Cfg->single, $id);
}

package BSE::TB::SiteUserQueryGroup;
use constant OWNER_TYPE => "G";
use Carp qw(confess);

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

sub member_ids {
  my ($self) = @_;

  if ($self->{sql_all}) {
    my $dbh = BSE::DB->single->dbh;
    my $values = $dbh->selectcol_arrayref($self->{sql_all});
    $values
      or confess "Cannot execute $self->{sql_all}: ", $dbh->errstr, "\n";

    return @$values;
  }
  else {
    return grep $self->contains_user($_), BSE::TB::SiteUsers->all_ids;
  }
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
