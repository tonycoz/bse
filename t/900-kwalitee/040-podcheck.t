#!perl -w
use strict;
use Test::More;
use Getopt::Long;
use ExtUtils::Manifest qw(maniread);
eval "use Pod::Checker 1.51;";
plan skip_all => "Pod::Checker 1.51 required for testing POD" if $@;
my $manifest = maniread();
my @pod = sort grep /\.(pm|pl|pod|PL)$/, keys %$manifest;

my $rebuild;
GetOptions("r" => \$rebuild);

my $known_issues_name = "t/data/known_pod_issues.txt";
my %expected;
unless ($rebuild) {
  plan tests => scalar(@pod);
  open my $exp_file, "<", $known_issues_name
    or die "Cannot open $known_issues_name: $!\n";
  while (<$exp_file>) {
    chomp;
    my ($filename, @error_found) = split /\t/, $_, 3;
    push @{$expected{$filename}}, \@error_found;
  }
}

my %found;
for my $file (@pod) {
  my $checker = My::Pod::Checker->new;
  $checker->parse_from_file($file, \*STDERR);
  my @errors = $checker->imager_errors;
  if ($rebuild) {
    $found{$file} = \@errors if scalar @errors;
  }
  else {
    my @diffs;
    my %exp = map { $_->[0] => $_->[1] } @{$expected{$file} || []};
    my %seen = map { $_->[0] => $_->[1] } @errors;
    my %all = map { $_ => 1 } keys %exp, keys %seen;
    for my $msg (sort keys %all) {
      my $old_count = $exp{$msg} || 0;
      my $new_count = $seen{$msg} || 0;
      if ($old_count && $new_count > $old_count) {
	push @diffs, "Added: $msg (from $old_count to $new_count)";
      }
      elsif (!$old_count) {
	push @diffs, "New: $msg ($new_count times)";
      }
      elsif ($new_count < $old_count) {
	push @diffs, "Fixed?: $msg (from $old_count to $new_count)";
      }
    }
    ok(!@diffs, "check errors for $file");
    for my $diff (@diffs) {
      $diff =~ s/\n/\n# /g;
      print "# $diff\n";
    }
  }
}

if ($rebuild) {
  open my $known_file, ">", $known_issues_name
    or die "Cannot create $known_issues_name; $!\n";
  binmode $known_file;
  for my $file (sort keys %found) {
    for my $issue (@{$found{$file}}) {
      print $known_file join("\t", $file, @$issue), "\n";
    }
  }
  close $known_file;
}

{
  # partly stolen from perl's t/porting/podcheck.t
  package My::Pod::Checker;
  use base 'Pod::Checker';

  my $line_reference;
  my $optional_location;

  BEGIN {
    my $location = qr/ \b (?:in|at|on|near) \s+ /xi;
    $optional_location = qr/ (?: $location )? /xi;
    $line_reference = qr/ [('"]? $optional_location \b line \s+
                             (?: \d+ | EOF | \Q???\E | - )
                             [)'"]? /xi;

  }

  sub new {
    my ($class) = @_;

    my $self = $class->SUPER::new(-quiet => 1,
				  -warnings => 200);
    $self->{imager_errors} = [];

    return $self;
  }

  sub poderror {
    my $self = shift;

    my $opts = shift;
    my $message;
    if (!ref $opts || ref $opts ne "HASH") {
      $message = join "", $opts, @_;
      my $line_number;
      if ($message =~ s/\s*($line_reference)//) {
	($line_number = $1) =~ s/\s*$optional_location//;
      }
      else {
	$line_number = '???';
      }
      $opts = { -msg => $message, -line => $line_number };
    }
    else {
      $message = $opts->{-msg};
    }
    $message =~ s/^\d+\s+//;

    # this message is so wrong
    $message =~ /unescaped <> in paragraph/ and return;

    # this one too
    $message =~ /No items in =over/ and return;

    push @{$self->{imager_errors}}, $opts;
  }

  sub imager_errors {
    # fold, spindle, mutilate
    my %by_error;
    for my $error (@{$_[0]{imager_errors}}) {
      ++$by_error{$error->{-msg}};
    }
    return
      (
       map [ $_, $by_error{$_} ],
       sort keys %by_error
      );
  }
}
