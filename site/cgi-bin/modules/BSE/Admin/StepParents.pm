package BSE::Admin::StepParents;
use strict;
use BSE::TB::Articles;
use BSE::TB::OtherParents;
use BSE::Util::SQL qw/date_to_sql/;

our $VERSION = "1.002";

sub add {
  my ($class, $parent, $child, $release, $expire) = @_;

  my %data;
  $data{parentId} = $parent->{id};
  $data{childId} = $child->{id};
  $data{parentDisplayOrder} = $data{childDisplayOrder} = time;
  $data{expire} = ($expire && date_to_sql($expire)) || '2999-12-31';
  $data{release} = ($release && date_to_sql($release)) || '2000-01-01';
  my @cols = BSE::TB::OtherParent->columns;
  shift @cols;

  # check for an existing entry
  my $existing = 
    BSE::TB::OtherParents->getBy(parentId=>$parent->{id}, childId=>$child->{id})
    and die "Entry already exists\n";

  my $otherprod = BSE::TB::OtherParents->add(@data{@cols})
    or die "Cannot add\n";

  return $otherprod;
}

sub del {
  my ($class, $parent, $child) = @_;

  my $existing = 
    BSE::TB::OtherParents->getBy(parentId=>$parent->{id}, childId=>$child->{id})
    or die "Entry doesn't exit";

  $existing->remove();
}

1;
