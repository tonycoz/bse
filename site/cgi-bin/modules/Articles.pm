package Articles;
use strict;
use Squirrel::Table;
use vars qw(@ISA $VERSION);
@ISA = qw(Squirrel::Table);
use Article;

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

1;
