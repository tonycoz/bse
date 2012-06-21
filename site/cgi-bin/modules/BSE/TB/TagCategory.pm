package BSE::TB::TagCategory;
use strict;
use base 'Squirrel::Row';

=head1 NAME

BSE::TB::TagCategory - represents a tag category

=head1 SYNOPSIS

  my $cat = Article->tag_category($name);

  my @deps = $cat->deps;

  $cat->set_deps(\@deps, \$error) or die;

=head1 METHODS

=over

=cut

our $VERSION = "1.000";

sub columns {
  qw(id cat owner_type);
}

sub table { 'bse_tag_categories' }

=item remove

Remove the category entry.

This B<does not> remove tags in this category.

=cut

sub remove {
  my ($self) = @_;

  BSE::DB->single->run("BSE::TB::TagCategoryDeps.deleteCat" => $self->id);

  $self->SUPER::remove();
}

=item json_data

Return a JSON representable form of the category.

=cut

sub json_data {
  my ($self) = @_;

  my $data = $self->data_only;
  $data->{name} = $self->name;
  $data->{dependencies} = [ $self->deps ];

  return $data;
}

=item deps

Returns the dependencies for the category as a list of strings.

=cut

sub deps {
  my ($self) = @_;

  require BSE::TB::TagCategoryDeps;
  return BSE::TB::TagCategoryDeps->getColumnBy
    (
     "depname",
     [
      [ cat_id => $self->id ],
     ],
     { order => "depname" },
    );
}

=item set_deps(\@deps, \$error)

Replace the list of tag dependencies for the category.

Returns true on success.

Returns false on failure storing an error code in $error.

=cut

sub set_deps {
  my ($self, $deps, $error) = @_;

  # check validity
  my @workdeps;
  for my $dep (@$deps) {
    my $name;
    my $error;
    if ((($name) = BSE::TB::Tags->name($dep))
	|| ($name = BSE::TB::Tags->valid_category($dep))) {
      push @workdeps, $name;
    }
    else {
      $$error = "badtag";
      return;
    }
  }

  my @current_deps = $self->_deps;
  my %unused_deps = map { lc $_->depname => $_ } @current_deps;

  my %seen;
  # remove duplicates
  @workdeps = grep !$seen{lc $_}++, @workdeps;

  my @add_deps;
  for my $dep (@workdeps) {
    unless (delete $unused_deps{lc $dep}) {
      push @add_deps, $dep;
    }
  }

  for my $add (@add_deps) {
    BSE::TB::TagCategoryDeps->make
	(
	 cat_id => $self->id,
	 depname => $add,
	);
  }

  for my $del (values %unused_deps) {
    $del->remove;
  }

  return 1;
}

=back

=head1 INTERNAL METHODS

=over

=item _deps

Returns the tage dependencies as objects.

=cut

sub _deps {
  my ($self) = @_;

  require BSE::TB::TagCategoryDeps;
  return BSE::TB::TagCategoryDeps->getBy2
    (
     [
      [ cat_id => $self->id ],
     ],
     { order => "depname" },
    );
}


1;

=back

=head1 AUTHOR

Tony Cook <tony@develop-help.com>

=cut

