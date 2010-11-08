package BSE::Index::Base;
use strict;

our $VERSION = "1.000";

1;

__END__

=head1 NAME

BSE::Index::Base - base class for BSE search engine indexers.

=head1 METHODS

An index must provide the following methods:

=over

=item new

Class method.  Supplied with the following named parameters:

=over

=item cfg

BSE::Cfg object or similar.

=item scores

Hash of field scores.  This can be ignored.

=item callback

Logging callback, optional.  A coderef that accepts a single string to
be logged.

=back

=item start_index

Object method called to start the indexing process.  No parameters.

=item process_article

Object method called to process a single article.  Accepts one
parameter, the article to be indexed.

=item end_index

Object method called to finish indexing.

=back

=cut

