package BSE::ImportSourceXLS;
use strict;
use base 'BSE::ImportSourceBase';
use Spreadsheet::ParseExcel;

our $VERSION = "1.000";

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
  my ($self, $importer, $filename) = @_;

  my $parser = Spreadsheet::ParseExcel->new;
  my $wb = $parser->Parse($filename)
    or die "Could not parse $filename";
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
