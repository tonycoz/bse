#!perl -w
use strict;
use DevHelp::LoaderData;
use BSE::MessageScanner;
use Test::More;

# check that the core message bases and defaults cover all of the ids
# used in BSE.

# load the data
my @base = _load("site/data/db/bse_msg_base.data");
my %base = map { $_->{id} => 1 } @base;
my @defs = _load("site/data/db/bse_msg_defaults.data");
my %defs = map { $_->{id} => 1 } @defs;

# scan for ids
my @msgs = BSE::MessageScanner->scan([ "site" ]);

# make them unique, we don't need a bunch of errors for one id
my %seen;
@msgs = grep !$seen{$_->[0]}, @msgs;

plan tests => 2 * scalar(@msgs);

for my $msg (@msgs) {
  my ($id, $file, $line) = @$msg;
  (my $subid = $id) =~ s/^msg://;
  ok($base{$subid}, "found base for $id ($file:$line)");
  ok($defs{$subid}, "found default for $id ($file:$line)");
}

sub _load {
  my ($in_name) = @_;

  open my $fh, "<", $in_name
    or die "Cannot open $in_name: $!";
  my $loader = DevHelp::LoaderData->new($fh);
  my @data;
  while (my $row = $loader->read) {
    push @data, $row;
  }

  return @data;
}
