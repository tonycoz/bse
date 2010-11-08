package BSE::TB::OwnedFiles;
use strict;
use base 'Squirrel::Table';
use BSE::TB::OwnedFile;

our $VERSION = "1.000";

sub rowClass {
  'BSE::TB::OwnedFile';
}

sub categories {
  my ($class, $cfg) = @_;

  my @cat_ids = split /,/, $cfg->entry("file categories", "ids", "");
  grep $_ eq "", @cat_ids
    or unshift @cat_ids, "";

  my @cats;
  for my $id (@cat_ids) {
    my $section = length $id ? "file category $id" : "file category empty";
    my $def_name = length $id ? ucfirst $id : "(None)";
    my $name = $cfg->entry($section, "name", $def_name);
    push @cats, +{ id => $id, name => $name };
  }

  return @cats;
}

1;
