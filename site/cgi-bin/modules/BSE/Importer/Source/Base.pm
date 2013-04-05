package BSE::Importer::Source::Base;
use strict;
use Config;

our $VERSION = "1.002";

=head1 NAME

BSE::Importer::Source::Base - base class for importer sources

=head1 SYNOPSIS

  [import profile foo]
  source=something derived from BSE::Importer::Source::Base

=head1 DESCRIPTION

This provides a trivial base class for importer sources.

New sources should have this in their @ISA as it will be updated to
provide default implementations of methods sources are required to
provide.

=head1 METHODS

=over

=item new()

Create a new importer source.

Sources should override this method.

=cut

sub new {
  my ($class, %opts) = @_;

  my $importer = delete $opts{importer};
  my $opts = delete $opts{opts};

  return bless
    {
    }, $class;
}

=back

=head1 SOURCE METHODS

Sources should provide the following methods:

=over

=item each_row()

  $source->each_row($importer, $filename);

Called by the importer to parse the source.

This should populate the storage used by get_column() and call 

  $importer->row($source)

for each row found.

C<$filename> can be either a filename or a file handle reference.

=item get_column()

  $source->get_column($column_number)

Return the data found in column C<$column_number> in the source row.

=item rowid()

Return a description of the current row.

=back

=cut

1;
