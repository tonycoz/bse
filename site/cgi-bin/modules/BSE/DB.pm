package BSE::DB;
require 5.005;
use strict;
use Carp qw(croak);
use Carp qw/confess/;

use vars qw($VERSION);
$VERSION = '1.00';

use Constants qw/$DBCLASS/;

my $file = $DBCLASS;
$file =~ s!::!/!g;
require "$file.pm";

sub single {
  $DBCLASS->_single();
}

sub query {
  my ($self, $name, @args) = @_;

  $self = BSE::DB->single unless ref $self;

  my $sth = $self->stmt($name);

  $sth->execute(@args)
    or croak "Cannot execute statement $name: ",$sth->errstr;
  my @results;
  while (my $row = $sth->fetchrow_hashref) {
    push(@results, { %$row } );
  }
  return @results;
}

sub run {
  my ($self, $name, @args) = @_;

  $self = BSE::DB->single unless ref $self;

  my $sth = $self->stmt($name);

  $sth->execute(@args)
    or confess "Cannot execute statement $name: ",$sth->errstr;
}

sub dbh {
  $_[0]{dbh};
}

1;

__END__

=head1 NAME

  BSE::DB - a wrapper class used by BSE to give a common interface to several databases

=head1 SYNOPSIS

  my $dh = BSE::DB->single;
  my $sth = $dh->stmt($stmt_name);
  $sth->execute() or die;
  my $id = $dh->insert_id($sth)

=head1 DESCRIPTION

BSE::DB->single() returns a wrapper object defined by the class
specified by $DBCLASS.

Currently only the following methods are defined:

=over

=item stmt($name)

Returns a statement based on the given name.

=item insert_id($sth)

After a statement is executed that inserts into a table that has an
auto defining key, eg. auto_increment on mysql or identity on T-SQL
databases.  This method returns the value of the inserted key.

=back

=head1 AUTHOR

Tony Cook <tony@develop-help.com>

=head1 SEE ALSO

bse.pod

=cut
