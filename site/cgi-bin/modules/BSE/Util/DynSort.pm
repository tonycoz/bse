package BSE::Util::DynSort;
use strict;

our $VERSION = "1.000";

use DevHelp::DynSort qw(tag_sorthelp);
use vars qw(@EXPORT_OK);
use base 'Exporter';
@EXPORT_OK = qw(sorter tag_sorthelp);

sub sorter {
  my (%opts) = @_;

  if ($opts{session} && $opts{name}) {
    unless ($opts{save}) {
      $opts{save} = [ \&_sorter_save, $opts{session}, $opts{name} ];
    }
    unless ($opts{get}) {
      $opts{get} = [ \&_sorter_get, $opts{session}, $opts{name} ];
    }
  }

  return DevHelp::DynSort::sorter(%opts);
}

sub _sorter_save {
  my ($session, $name, @parms) = @_;

  $session->{"sort_$name"} = \@parms;
}

sub _sorter_get {
  my ($session, $name) = @_;

  my $saved = $session->{"sort_$name"}
    or return;

  return @$saved;
}

1;
