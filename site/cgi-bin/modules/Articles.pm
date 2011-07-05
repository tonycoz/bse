package Articles;
use strict;
use Squirrel::Table;
use vars qw(@ISA $VERSION);
require BSE::TB::TagOwners;
@ISA = qw(Squirrel::Table BSE::TB::TagOwners);
use Article;

our $VERSION = "1.002";

sub rowClass {
  return 'Article';
}

# returns a list of articles which are sections
sub sections {
  my ($self) = @_;

  return $self->getBy('level', 1);
}

# returns a list of articles which are sub sections
sub subsections {
  my ($self) = @_;

  return $self->getBy('level', 2);
}

# child articles of the given child id
sub children {
  my ($self, $id) = @_;

  return $self->getBy('parentid', $id);
}

# children of the given article that are listed and in the display order
sub listedChildren {
  my ($self, $id) = @_;
  my ($year, $month, $day) = (localtime)[5,4,3];
  my $today = sprintf("%04d-%02d-%02d 00:00:00ZZZ", $year+1900, $month+1, $day);
  my @work = $self->children($id);
  return sort { $b->{displayOrder} <=> $a->{displayOrder} }
    grep { $_->{listed} && $today ge $_->{release} 
	     && $today le $_->{expire}} @work;
}

sub summary {
  BSE::DB->query('articlesList');
}

sub allids {
  my ($self) = @_;

  if (ref $self) {
    return map $_->{id}, $self->all;
  }
  else {
    return map $_->{id}, BSE::DB->query('Articles.ids');
  }
}

sub visible_stepkids {
  my ($self, $id) = @_;

  use BSE::Util::SQL qw/now_sqldate/;
  my $today = now_sqldate();

  return Articles->getSpecial('visibleStepKids', $id, $today);
}

sub all_visible_kids {
  my ($self, $id) = @_;

  require 'OtherParents.pm';

  my @otherlinks = OtherParents->getBy(parentId=>$id);
  my @normalkids = Articles->listedChildren($id);
  my %order = (
	       (map { $_->{id}, $_->{displayOrder} } @normalkids ),
	       (map { $_->{childId}, $_->{parentDisplayOrder} } @otherlinks),
	      );
  my @stepkids = $self->visible_stepkids($id);
  my %kids = map { $_->{id}, $_ } @stepkids, @normalkids;

  return @kids{ sort { $order{$b} <=> $order{$a} } keys %kids };
}

sub all_visible_kid_tags {
  my ($self, $id) = @_;

  require BSE::TB::Tags;
  require BSE::TB::TagMembers;
  return
    {
     tags => [ BSE::TB::Tags->getSpecial(allkids => $id, $id) ],
     members => [ BSE::TB::TagMembers->getSpecial(allkids => $id, $id) ],
    };
}

sub global_files {
  my ($self) = @_;

  require BSE::TB::ArticleFiles;
  return BSE::TB::ArticleFiles->getBy(articleId => -1);
}

=item allkid_summary($parent_id)

Return a list of hash per child, each with id, displayOrder sorted for
display.

Entries with step_id are for step children of $parent_id.

=cut

sub allkid_summary {
  my ($class, $parent_id) = @_;

  my @child_order = BSE::DB->query(bseChildOrder => $parent_id);
  my @stepchild_order = BSE::DB->query(bseStepchildOrder => $parent_id);

  return sort { $b->{displayOrder} <=> $a->{displayOrder} }
    ( @child_order, @stepchild_order );
}

sub reorder_child {
  my ($class, $parent_id, $child_id, $after_id) = @_;

  my @child_order = $class->allkid_summary($parent_id);

  my ($child_index) = grep $child_order[$_]{id} == $child_id, 0..$#child_order
    or return; # nothing to do, it's not a child
  my @order = map $_->{displayOrder}, @child_order;

  if ($child_index > 0 && $child_order[$child_index-1]{id} == $after_id
      || $child_index == 0 && $after_id == 0) {
    # trivial success
    return 1;
  }

  # remove the child from the order
  my ($child) = splice(@child_order, $child_index, 1);

  my $start_index;
  if ($after_id == 0) {
    unshift @child_order, $child;
    $start_index = 0;
  }
  else {
    my ($after_index) = grep $child_order[$_]{id} == $after_id, 0..$#child_order
      or return; # after not found, nothing to do

    splice(@child_order, $after_index+1, 0, $child);
    $start_index = $after_index + 1;
  }

  for my $index (0 .. $#order) {
    my $child = $child_order[$index];
    if ($child->{step_id}) {
      BSE::DB->run(bseSetStepOrder => $order[$index], $child->{step_id});
    }
    else {
      BSE::DB->run(bseSetArticleOrder => $order[$index], $child->{id});
    }
  }

  return 1;
}

sub all_tags {
  my ($self, @more_rules) = @_;
  return BSE::TB::Tags->getBy2
    (
     [ 
      [ owner_type => Article->tag_owner_type ],
      @more_rules
     ],
     { order => "cat, val" },
    );
}

1;
