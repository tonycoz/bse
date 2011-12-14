package BSE::NLFilter::SQL;
use strict;
use Carp 'confess';

our $VERSION = "1.001";

sub new {
  my ($class, %opts) = @_;
  
  defined $opts{cfg} or confess "No cfg option";
  defined $opts{data} or confess "No data option";
  defined $opts{index} or confess "No index option";

  return bless \%opts, $class;
}

sub tags {
  return;
}

sub members {
  my ($self, $cgi) = @_;

  my %entries = $self->{cfg}->entries($self->{data});
  my ($prefix, $suffix) = delete @entries{qw/prefix suffix/};

  my $sql = $prefix;
  for my $key (keys %entries) {
    if ($cgi->param($key)) {
      $sql .= " " . $entries{$key};
    }
  }
  $sql .= " " . $suffix;

  my $dbh = BSE::DB->single->dbh;
  my $sth = $dbh->prepare($sql)
    or die "Could not prepare $sql: ",$dbh->errstr;
  $sth->execute
    or die "Could not execute $sql: ",$dbh->errstr;
  my @ids;
  my $id;
  while (my $row = $sth->fetchrow_arrayref) {
    push @ids, $row->[0];
  }

  return @ids;
}

1;

__END__

=head1 NAME

BSE::NLFilter::SQL - SQL based newsletter filter.

=head1 SYNOPSIS

  [newsletter filters]
  criteria1=BSE::NLFilter::SQL;section name

=head1 DESCRIPTION

This is the original newsletter subcriber filter for BSE.  This works
fairly simply, but requires some thought to use.

To use this filter, add an entry to the [newsletter filters] section
of bse.cfg (or an included config file), with the value being
C<BSE::NLFilter::SQL> followed by a semi-colon, and the by the name of
the section to configure this instance of the filter from.

For example:

  [newsletter filters]
  criteria1=BSE::NLFilter::SQL;section name

The given section must contain 2 special keys:

=over

=item prefix

SQL prefix - the beginning of an SQL statement.

=item suffix

SQL suffix - the end of a SQL statement.

=back

The section should also contain one or more other keys.  In each case
the key is the name of a CGI parameter and the value is a SQL
fragment.

For example, you might want to limit to users starting with a, b, or
c:

  [section name]
  ; the 1=0 makes the leading "or " valid on the other fragments
  prefix=select id from bse_siteusers where 1=0
  suffix=
  leadinga=or userId like 'a%'
  leadingb=or userId like 'b%'
  leadingc=or userId like 'c%'

(Yes, this exampe is contrived.)

There is nothing preventing joins or more complex SQL.

The only requirement is that the SQL result set includes a single
column which is the id from the bse_siteusers table for that user.

You will need to edit the admin/subs/send_filter.tmpl template to add
form elements to accept the CGI parameters above.  For our example we
might have:

  <tr>
    <th colspan="3">Filters</th>
  </tr>
  <tr>
    <th>Filters:</th>
    <td>
      <input type="checkbox" name="criteria1" value="1" /> Filter by Leading letter
    </td>
  </tr>
  <tr>
    <th>Category:</th>
    <td>
      <input type="checkbox" name="leadinga" value="1" /> Leading A<br />
      <input type="checkbox" name="leadingb" value="1" /> Leading B<br />
      <input type="checkbox" name="leadingc" value="1" /> Leading C
    </td>
  </tr>

You may also want to modify admin/subs/filter_preview.tmpl to display
any CGI parameters your filter uses.

=head1 AUTHOR

Tony Cook <tony@develop-help.com>

=head1 REVISION

$Revision$

=cut
