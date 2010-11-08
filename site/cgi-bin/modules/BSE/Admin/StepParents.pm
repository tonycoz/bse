package BSE::Admin::StepParents;
use strict;
use Articles;
use OtherParents;
use BSE::Util::SQL qw/date_to_sql/;

our $VERSION = "1.000";

sub add {
  my ($class, $parent, $child, $release, $expire) = @_;

  my %data;
  $data{parentId} = $parent->{id};
  $data{childId} = $child->{id};
  $data{parentDisplayOrder} = $data{childDisplayOrder} = time;
  $data{expire} = ($expire && date_to_sql($expire)) || '2999-12-31';
  $data{release} = ($release && date_to_sql($release)) || '2000-01-01';
  my @cols = OtherParent->columns;
  shift @cols;

  # check for an existing entry
  my $existing = 
    OtherParents->getBy(parentId=>$parent->{id}, childId=>$child->{id})
    and die "Entry already exists\n";

  my $otherprod = OtherParents->add(@data{@cols})
    or die "Cannot add\n";

  return $otherprod;
}

sub del {
  my ($class, $parent, $child) = @_;

  my $existing = 
    OtherParents->getBy(parentId=>$parent->{id}, childId=>$child->{id})
    or die "Entry doesn't exit";

  $existing->remove();
}

1;
