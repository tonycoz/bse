package Article;
use strict;
# represents an article from the database
use Squirrel::Row;
use vars qw/@ISA/;
@ISA = qw/Squirrel::Row/;

sub columns {
  return qw/id parentid displayOrder title titleImage body
    thumbImage thumbWidth thumbHeight imagePos
    release expire keyword template link admin threshold
    summaryLength generator level listed lastModified/;
}

sub step_parents {
  my ($self) = @_;

  Articles->getSpecial('stepParents', $self->{id});
}

sub visible_step_parents {
  my ($self) = @_;

  use BSE::Util::SQL qw/now_datetime/;
  my $now = now_datetime();
  grep $_->{release} le $now && $now le $_->{expire}, $self->step_parents;
}

sub stepkids {
  my ($self) = @_;

  if ($self->{generator} eq 'Generate::Catalog') {
    require 'Products.pm';
    return Products->getSpecial('stepProducts', $self->{id});
  }
  return ();
}

sub visible_stepkids {
  my ($self) = @_;

  if ($self->{generator} eq 'Generate::Catalog') {
    use BSE::Util::SQL qw/now_sqldate/;
    require 'Products.pm';
    my $today = now_sqldate();

    return Products->getSpecial('visibleStep', $self->{id}, $today);
  }
  
  return ();
}

# returns a list of all children in the correct sort order
# this is a bit messy
sub allkids {
  my ($self) = @_;

  require 'OtherParents.pm';

  my @otherlinks = OtherParents->getBy(parentId=>$self->{id});
  my @normalkids = Articles->children($self->{id});
  my %order = (
	       (map { $_->{id}, $_->{displayOrder} } @normalkids ),
	       (map { $_->{childId}, $_->{parentDisplayOrder} } @otherlinks),
	      );
  my @stepkids = $self->stepkids;
  my %kids = map { $_->{id}, $_ } @stepkids, @normalkids;

  return @kids{ sort { $order{$b} <=> $order{$a} } keys %kids };
}

# returns a list of all visible children in the correct sort order
# this is a bit messy
sub all_visible_kids {
  my ($self) = @_;

  require 'OtherParents.pm';

  my @otherlinks = OtherParents->getBy(parentId=>$self->{id});
  my @normalkids = Articles->listedChildren($self->{id});
  my %order = (
	       (map { $_->{id}, $_->{displayOrder} } @normalkids ),
	       (map { $_->{childId}, $_->{parentDisplayOrder} } @otherlinks),
	      );
  my @stepkids = $self->visible_stepkids;
  my %kids = map { $_->{id}, $_ } @stepkids, @normalkids;

  return @kids{ sort { $order{$b} <=> $order{$a} } keys %kids };
}

1;
