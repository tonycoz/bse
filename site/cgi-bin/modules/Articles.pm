package Articles;
use strict;
use Squirrel::Table;
use vars qw(@ISA $VERSION);
require BSE::TB::TagOwners;
@ISA = qw(Squirrel::Table BSE::TB::TagOwners);
use Article;

our $VERSION = "1.005";

=head1 NAME

Articles - BSE's article collection

=head1 SYNOPSIS

  use Articles;

  my $article = Articles->make(...);
  my $article = Articles->getByPkey($id)
  # etc

=head1 DESCRIPTION

The collective class for BSE articles.

=head1 USEFUL METHODS

=over

=cut

sub rowClass {
  return 'Article';
}

=item sections

Returns a list of articles which are sections

=cut

sub sections {
  my ($self) = @_;

  return $self->getBy('level', 1);
}

=item subsections

Returns a list of articles which are sub sections

=cut

sub subsections {
  my ($self) = @_;

  return $self->getBy('level', 2);
}

=item children($id)

Child articles of the given article id

=cut

sub children {
  my ($self, $id) = @_;

  return $self->getBy('parentid', $id);
}

=item listedChildren($id)

Children of the given article id that are listed and in the display
order

=cut

sub listedChildren {
  my ($self, $id) = @_;
  my ($year, $month, $day) = (localtime)[5,4,3];
  my $today = sprintf("%04d-%02d-%02d 00:00:00ZZZ", $year+1900, $month+1, $day);
  my @work = $self->children($id);
  return sort { $b->{displayOrder} <=> $a->{displayOrder} }
    grep { $_->{listed} && $today ge $_->{release} 
	     && $today le $_->{expire}} @work;
}

=item summary

Return a list of hashes with article id and title for every article.

=cut

sub summary {
  BSE::DB->query('articlesList');
}

=item allids

Return a list of all article ids.

=cut

sub allids {
  my ($self) = @_;

  if (ref $self) {
    return map $_->{id}, $self->all;
  }
  else {
    return map $_->{id}, BSE::DB->query('Articles.ids');
  }
}

=item visible_stepkids($id)

Return a list of visible stepkids of the given article id.

=cut

sub visible_stepkids {
  my ($self, $id) = @_;

  use BSE::Util::SQL qw/now_sqldate/;
  my $today = now_sqldate();

  return Articles->getSpecial('visibleStepKids', $id, $today);
}

=item all_visible_kids($id)

Return a list of all visible children of the given article id.

=cut

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

=item all_visible_kid_tags($id)

Return a hash with two keys, C<tags> being all tags for all visible
children of C<$id>, and C<members> being all tag member objects for
all visible children of C<$id>.

=cut

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

=item global_files

Return a list of global files.

=cut

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

=item reorder_child($parent_id, $child_id, $after_id)

Move article C<$child_id> after C<$after_id> in the all children list
of article C<$after_id>.

Returns a true value on success.

=cut

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

=item categories

Return a list of all configured article categories.

Each entry is a hash containing C<id> and C<name>.

=cut

sub categories {
  my $cfg = BSE::Cfg->single;

  my @cat_ids = split /,/, $cfg->entry("article categories", "ids", "");
  grep $_ eq "", @cat_ids
    or unshift @cat_ids, "";

  my @cats;
  for my $id (@cat_ids) {
    my $section = length $id ? "article category $id" : "article category empty";
    my $def_name = length $id ? ucfirst $id : "(None)";
    my $name = $cfg->entry($section, "name",
			   $cfg->entry("article categories", $id, $def_name));
    push @cats, +{ id => $id, name => $name };
  }
  
  return @cats;
}

1;

=back

=head1 AUTHOR

Tony Cook <tony@develop-help.com>

=cut

