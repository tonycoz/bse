package BSE::Importer::Source::XLS;
use strict;
use base 'BSE::Importer::Source::Base';
use Spreadsheet::ParseExcel;

our $VERSION = "1.003";

=head1 NAME

BSE::Importer::Source::XLS - import source for XLS files.

=head1 SYNOPSIS

   [import profile foo]
   ; XLS is the default and can be ommitted
   source=XLS
   ; these are the defaults
   sheet=1
   skiprows=1

=head1 DESCRIPTION

Uses an Excel XLS file (not XLSX) as a data source.

=head1 CONFIGURATION

The following extra configuration can be set in the profile's
configuration:

=over

=item *

C<sheet> - the sheet number to import.  Default: 1.

=item *

C<skiprows> - the number of rows for skip at the top, eg. for column
headings.  Default: 1.

=back

=cut

sub new {
  my ($class, %opts) = @_;

  my $self = $class->SUPER::new(%opts);

  my $importer = delete $opts{importer};
  my $opts = delete $opts{opts};

  $self->{sheet} = $importer->cfg_entry("sheet", 1);
  $self->{skiprows} = $importer->cfg_entry('skiprows', 1);

  return $self;
}

sub each_row {
  my ($self, $importer, $file) = @_;

  my $tmp;

  if (ref $file && !$file->can("seek") && defined fileno($file)) {
    # workaround a problem in CGI.pm, handle() returns an IO::Handle
    # instead of an IO::File
    $tmp = $file; # keep it live until the end of the function
    require IO::File;
    $file = IO::File->new_from_fd(fileno($file), "<");
  }

  my $parser = Spreadsheet::ParseExcel->new;
  my $wb = $parser->Parse($file)
    or die "Could not parse source as XLS\n";
  $self->{sheet} <= $wb->{SheetCount}
    or die "No enough worksheets in input\n";
  $self->{ws} = ($wb->worksheets)[$self->{sheet}-1]
    or die "No worksheet found at $self->{sheet}\n";

  my ($minrow, $maxrow) = $self->{ws}->RowRange;
  for my $rownum ($self->{skiprows} ... $maxrow) {
    $self->{rownum} = $rownum;
    $importer->row($self);
  }
}

sub get_column {
  my ($self, $colnum) = @_;

  my $cell = $self->{ws}->get_cell($self->{rownum}, $colnum-1);
  if (defined $cell) {
    return $cell->value;
  }
  else {
    return '';
  }
}

sub rowid {
  my $self = shift;

  return "Row " . ($self->{rownum}+1);
}

1;
