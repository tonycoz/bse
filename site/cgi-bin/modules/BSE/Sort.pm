package BSE::Sort;
use strict;
use vars qw/@EXPORT @ISA/;
require 'Exporter.pm';
@ISA = qw(Exporter);
@EXPORT = qw(bse_sort);

our $VERSION = "1.001";

my %backwhacked =
  (
   "\\"=> "\\",
   n => "\n",
   r => "\r",
   '"' => '"',
  );

=item bse_sort(\%types, $spec, @data)

Sort and/or filter the supplied list in C<@data> based on the
sort/filter specification in C<$spec> using the column types in
C<%types>

C<$spec> is a string containing either or both of a sort specification
followed by a filter specification.

A sort specification is C<sort=> followed by a comma separated list of
columns to sort.  A column name can have a preceding C<+> to indicate
(the default) ascending sort, or C<-> for a descending sort.

A filter specification is a space separated list of comparisons.

Each comparison is a column name, operator and value.

Possible operators are the standard numeric operators and C<=~>.

The type of comparison (numeric or string) depends on whether the
value is a number or a quoted string.

The value for the C<=~> operator must be a regexp formatted as
C</regexp/flags>.

=cut

sub bse_sort {
  my ($types, $opts, @data) = @_;

  my @filters;
  my @sorts;
  while ($opts) {
    if ($opts =~ s/^\s*sort=//) {
      while ($opts =~ s/^([+-]?)(\w+)//) {
	my ($dir, $field) = ($1, $2);
	if ($types->{$field} && $types->{$field} eq 'n') {
	  push(@sorts, $dir eq '-' ? sub { $b->{$field} <=> $a->{$field} }
	       : sub { $a->{$field} <=> $b->{$field} });
	}
	else {
	  push(@sorts, $dir eq '-' ? sub { $b->{$field} cmp $a->{$field} }
	       : sub { $a->{$field} cmp $b->{$field} });
	}
	$opts =~ s/\s*,\s*// or last;
      }
    }
    elsif ($opts =~ s/^\s*filter=//) {
      while ($opts =~ s/^\s*(\w+)\s*//) {
	my $field = $1;
	if ($opts =~ s/^\s*(==|!=|>=|<=|<|>|=~)//) {
	  my $op = $1;
	  if ($op eq '=~' && $opts =~ s!\s*/((?:[^\\/]|\\[\\/])+)/(i?)!!) {
	    my $value = $1;
	    my $flag = $2;
	    push(@filters, sub { $_->{$field} =~ /(?$flag:$value)/ });
	  }
	  elsif ($op ne '=~' && $opts =~ s/\s*(\d+)//) {
	    my $value = $1;
	    if ($op eq '==') {
	      push(@filters, sub { $_->{$field} == $value });
	    }
	    elsif ($op eq '!=') {
	      push(@filters, sub { $_->{$field} != $value });
	    }
	    elsif ($op eq '>=') {
	      push(@filters, sub { $_->{$field} >= $value });
	    }
	    elsif ($op eq '<=') {
	      push(@filters, sub { $_->{$field} <= $value });
	    }
	    elsif ($op eq '>') {
	      push(@filters, sub { $_->{$field} > $value });
	    }
	    elsif ($op eq '<') {
	      push(@filters, sub { $_->{$field} < $value });
	    }
	  }
	  elsif ($opts =~ s/"([^"]+)(")//
		 || $opts =~ s/'([^']+)(')//) {
	    my ($value, $quote) = ($1, $2);
	    if ($quote eq '"') {
	      $value =~ s/\\([\\nr"])/$backwhacked{$1} || $1/ge;
	    }
	    if ($op eq '==') {
	      push(@filters, sub { $_->{$field} eq $value });
	    }
	    elsif ($op eq '!=') {
	      push(@filters, sub { $_->{$field} ne $value });
	    }
	    elsif ($op eq '>=') {
	      push(@filters, sub { $_->{$field} ge $value });
	    }
	    elsif ($op eq '<=') {
	      push(@filters, sub { $_->{$field} le $value });
	    }
	    elsif ($op eq '>') {
	      push(@filters, sub { $_->{$field} gt $value });
	    }
	    elsif ($op eq '<') {
	      push(@filters, sub { $_->{$field} lt $value });
	    }
	    
	  }
	}
	else {
	  push(@filters, sub { $_->{$field} });
	}
      }
    }
    else {
      last;
    }
  }

  if (@filters) {
    @data = grep 
      { 
	my $result = 1;
	for my $entry (@filters) { 
	  $result = $result && $entry->();
	}
	$result;
      } @data;
  }
  
  if (@sorts) {
    @data = sort
      {
	my $result = 0;
	for my $entry (@sorts) {
	  $result = $entry->()
	    and last;
	}
	$result;
      } @data;
  }

  return @data;
}

1;

__END__

=head1 NAME

  BSE::Sort - general sorter

=head1 SYNOPSIS

  use BSE::Sort;
  my @records = bse_sort { field=>'type' }, $opts, @data;

=head1 DESCRIPTION

A function intended to be used from iterator reset functions.  Can be used
to filter and the objects to be iterated over.

=cut
