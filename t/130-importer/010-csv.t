#!perl -w
use strict;
use Test::More tests => 6;
use BSE::Cfg;
BEGIN {
  eval "require Text::CSV;"
    or plan skip_all => "Text::CSV not available";
}
use BSE::Importer::Source::CSV;

{
  my $cfg = BSE::Cfg->new_from_text(text => <<CFG);
[import profile test]
source=CSV
CFG
  my $importer = DummyImporter->new(columns => 3, cfg => $cfg);
  my $src = BSE::Importer::Source::CSV->new
    (
     importer => $importer,
     opts => { profile => "test", cfg => $cfg },
    );
  ok($src, "make a CSV source");

  $src->each_row($importer, "t/data/importer/basic.csv");
  is_deeply($importer->{rows},
      [
       [ "Line 2", 1, 2, 3 ],
       [ "Line 3", qw(abc def hij) ],
      ], "check data read");
}

{
  my $cfg = BSE::Cfg->new_from_text(text => <<'CFG');
[import profile test]
source=CSV
sep_char=\t
escape_char=\r
quote_char=\f
CFG
  my $importer = DummyImporter->new(columns => 3, cfg => $cfg);
  my $src = BSE::Importer::Source::CSV->new
    (
     importer => $importer,
     opts => { profile => "test", cfg => $cfg },
    );
  ok($src, "make a CSV source with escapes");
  is($src->{csv_opts}{sep_char}, "\t", "check sep_char escaping");
  is($src->{csv_opts}{escape_char}, "\r", "check escape_char escaping");
  is($src->{csv_opts}{quote_char}, "\f", "check quote_char escaping");
}

package DummyImporter;

sub new {
  my ($class, %opts) = @_;
  $opts{rows} = [];

  return bless \%opts, $class;
}

sub row {
  my ($self, $src) = @_;

  my @row = $src->rowid;
  for my $col (1 .. $self->{columns}) {
    push @row, $src->get_column($col);
  }
  push @{$self->{rows}}, \@row;
}

sub cfg_entry {
  my ($self, $key, $def) = @_;

  $self->{cfg}->entry('import profile test', $key, $def);
}

sub profile {
  "test";
}
