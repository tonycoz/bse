package BSE::Importer::Target::Base;
use strict;

our $VERSION = "1.001";

=head1 NAME

BSE::Importer::Target::Base - base class for importer targets

=head1 SYNOPSIS

  # done by BSE::Importer
  my $target = $target_class->new(importer=>$imp, opts => \%opts);
  ...
  $target->start($imp);
  # for each row:
  $target->row($imp, \%entry, \@parents);

=head1 DESCRIPTION

BSE::Importer::Target::Base is the base class for import targets.
Currently it only provides a base new() method, but may provide others
in the future.

This class has no specific configuration.

=head1 METHODS

=over

=item new()

Create a new target object.  Expects the following arguments:

=over

=item *

C<importer> - the importer object

=item *

C<opts> - the options supplied to the importer object new() method.

=back

=cut

sub new {
  my ($class, %opts) = @_;

  my $self = bless {}, $class;

  return $self;
}

1;

=back

=head1 TARGET METHODS

Target classes should provide the following methods:

=over

=item start()

  $target->start($importer)

Called before processing of rows from the source starts.  This can be
used for per file initialization.

=item row()

  $target->row($importer, \%entry, \@parents)

Called for each row of source data.

C<%entry> contains the data loaded from the source, including any
derived from C<set_> and C<xform_> configuration.

C<@parents> contains the data loaded from the C<cat1> .. C<cat3>
columns.

=back

=head1 AUTHOR

Tony Cook <tony@develop-help.com>

=cut
