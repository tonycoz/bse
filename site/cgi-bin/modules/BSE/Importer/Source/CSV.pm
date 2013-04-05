package BSE::Importer::Source::CSV;
use strict;
use base 'BSE::Importer::Source::Base';
use Text::CSV;

our $VERSION = "1.001";

my @text_csv_options = qw(quote_char escape_char sep_char binary allow_loose_quotes allow_loose_escapes allow_whitespace);

my @escape_options = qw(quote_char escape_char sep_char);

=head1 NAME

BSE::Importer::Source::CSV - import source for CSV files.

=head1 SYNOPSIS

   [import profile foo]
   source=CSV
   ; these are the defaults
   skiplines=1
   binary=1
   quote_char="
   sep_char=,
   escape_char="
   allow_loose_quotes=0
   allow_loose_escaped=0
   allow_whitespace=0
   encoding=utf-8

=head1 DESCRIPTION

Uses CSV (comma separated values) text files a data source.

=head1 CONFIGURATION

The following extra configuration can be set in the profile's
configuration, (mostly better described in L<Text::CSV>.

=over

=item *

C<skiplines> - the number of lines for skip at the top, eg. for column
headings.  Default: 1.

=item *

C<binary> - whether the file should be treated as binary.  The default
is typically correct. Default: 1.

=item *

C<sep_char> - the separator character between columns.  Default: ",".
To use tab:

  sep_char=\t

=item *

C<allow_whitespace> - set to true to ignore whitespace around the
separator.  Default: 0.

=item *

C<encoding> - the character encoding to use in the input text.
Default: "utf-8".

=item *

C<quote_char> - the character used for quoting fields containing
blanks or separators.  Default: '"'.

=item *

C<escape_char> - the character used for quote escapes.  Default: '"'.

=back

=cut

sub new {
  my ($class, %opts) = @_;

  my $self = $class->SUPER::new(%opts);

  my $importer = delete $opts{importer};
  my $opts = delete $opts{opts};

  $self->{skiplines} = $importer->cfg_entry('skiplines', 1);

  $self->{encoding} = $importer->cfg_entry('encoding', 'utf-8');
  my %csv_opts = ( binary => 1 );
  for my $opt (@text_csv_options) {
    my $val = $importer->cfg_entry($opt);
    defined $val and $csv_opts{$opt} = $val;
  }

  for my $opt (@escape_options) {
    if (defined (my $val = $csv_opts{$opt})) {
      if ($val =~ /\A\\(?:[nrtfbae]|x[0-9a-fA-F]{2}|[0-7]{1,3}|c.)\z/) {
	$csv_opts{$opt} = eval '"' . $val . '"';
      }
    }
  }

  $self->{csv_opts} = \%csv_opts;

  return $self;
}

sub each_row {
  my ($self, $importer, $filename) = @_;

  my $fh;

  if (ref $filename) {
    $fh = $filename;
    binmode $fh, ":encoding($self->{encoding})";
  }
  else {
    open $fh, "<:encoding($self->{encoding})", $filename
      or die "Cannot open file $filename: $!\n";
  }

  my $csv = Text::CSV->new($self->{csv_opts})
    or die "Cannot use CSV: ", Text::CSV->error_diag(), "\n";

  for my $line (1 .. $self->{skiplines}) {
    my $row = $csv->getline($fh);
    if (!$row) {
      if ($csv->eof) {
	die "Ran out of rows reading the headers\n";
      }
      else {
	die "Error reading header rows: ", $csv->error_diag, "\n";
      }
    }
  }

  while (my $row = $csv->getline($fh)) {
    $self->{row} = $row;
    $self->{line} = $.;
    $importer->row($self);
  }
}

sub get_column {
  my ($self, $colnum) = @_;

  $colnum > @{$self->{row}}
    and return '';

  return $self->{row}[$colnum-1];
}

sub rowid {
  my $self = shift;

  return "Line " . $self->{line};
}

1;

=head1 AUTHOR

Tony Cook <tony@develop-help.com>

=head1 SEE ALSO

L<BSE::Importer>

=cut
