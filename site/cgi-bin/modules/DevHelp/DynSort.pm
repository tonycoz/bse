package DevHelp::DynSort;
use strict;
use vars qw(@EXPORT_OK);
use base 'Exporter';
@EXPORT_OK = qw(sorter tag_sorthelp);
use Carp 'confess';

sub sorter {
  my (%opts) = @_;
  
  my $cgi = $opts{cgi}
    or confess "No cgi object supplied.";
  my $data = $opts{data}
    or confess "No data supplied";
  my $fields = $opts{fields} || {};
  my $def_sortby = $opts{sortby};
  my $def_reverse = $opts{reverse};
  my $sortby_param = $opts{sortparam} || 's';
  my $tie_field = $opts{tiefield};
  my $reverse_param = $opts{reverseparam} || 'r';

  my $sortby = $cgi->param($sortby_param);
  defined $sortby && $sortby =~ /^\w+$/ or $sortby = $def_sortby;
  my $reverse = $cgi->param($reverse_param);
  defined $reverse or $reverse = $def_reverse;
  $reverse = $reverse ? 1 : 0; # make sure it's a number

  if (@$data && $sortby) {
    exists $data->[0]{$sortby} or $sortby = $def_sortby;
    exists $data->[0]{$sortby} or $sortby = '';
    if (defined $sortby && $sortby ne '') {
      my $tie_numeric;
      if (defined $tie_field) {
	exists $data->[0]{$tie_field}
	  or confess "No tie breaker field $tie_field in data";
	$tie_numeric = 
	  $fields && exists $fields->{$tie_field} && $fields->{$tie_field}{numeric};
      }
      
      my $numeric = 
	$fields && exists $fields->{$sortby} && $fields->{$sortby}{numeric};
      @$data = sort
	{
	  my $left = $a->{$sortby};
	  defined $left or $left = '';
	  my $right = $b->{$sortby};
	  defined $right or $right = '';
	  my $cmp = $numeric ? $left <=> $right : lc $left cmp lc $right;
	  if (!$cmp && $tie_field) {
	    $cmp = $tie_numeric 
	      ? $a->{$tie_field} <=> $b->{$tie_field}
		: lc $a->{$tie_field} cmp lc $b->{$tie_field};	
	  }
	  $cmp = -$cmp if $reverse;
	  $cmp;
	} @$data;
    }
  }

  return ($sortby, $reverse);
}

sub tag_sorthelp {
  my ($sortby, $reverse, $args) = @_;

  if ($args eq $sortby) {
    my $rev = $reverse ? 0 : 1;
    return "s=$args&r=$rev";
  }
  else {
    return "s=$args&r=0";
  }
}

1;

=head1 NAME

  DevHelp::DynSort - sort listings at run-time.

=head1 SYNOPSIS

  my @data = ....; # array of hashes
  my ($sortby, $reverse) =
     sorter(data=>\@data, cgi=>$cgi, ...),

  my %acts;
  %acts = 
    (
     ...
     sortby => $sortby,
     reverse => $reverse,
    );

=head1 DESCRIPTION

Intended for use in sorting supplied data based on user criteria.

=head2 Required Parameters

=over

=item data

An array ref of hashes.  This is sorted in place.

=item cgi

A CGI.pm compatible CGI object.  Only the param() method is called.

=back

=head2 Optional Parameters

=over

=item fields

Hash of hashes, where the key at the top level is the field name, and
the value configuration information for that field.

The only field in the configuration information is 'numeric' which
marks the field for numeric sorting if non-zero.

=item sortby

Default field to sort by.  No default (if no sort order is provided by
the user and this value isn't set, then the data isn't sorted.)

=item reverse

Default reversal.  Default: zero (ascending order).

=item sortparam

The name of the CGI parameter to get the sort order field from.
Default 's'.

=item reverseparam

The name of the CGI parameter to get the reversal from.  Default 'r'.

=item tiefield

Name of the field to use for breaking ties in the sort order.
Default: ties aren't broken.  If this is set to a field name then that
field will be used to break ties in sorting by the primary sort field.

=back

=head1 AUTHOR

Tony Cook <tony@develop-help.com>

=cut
