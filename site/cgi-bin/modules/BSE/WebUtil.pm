package BSE::WebUtil;
use strict;

use vars qw(@EXPORT_OK @ISA);
require Exporter;
@ISA = qw(Exporter);
@EXPORT_OK = qw(refresh_to refresh_to_admin);

sub refresh_to {
  my ($where) = @_;

  #print "Content-Type: text/html\n";
  #print qq!Refresh: 0; url=$where\n\n<html></html>\n!;
  print "Status: 303\n";
  print "Location: $where\n\n";
}

sub refresh_to_admin {
  my ($cfg, $where) = @_;

  use Carp 'confess';
  defined $where or confess 'No url supplied';

  unless ($where =~ /^\w+:/) {
    require BSE::CfgInfo;
    my $adminbase = BSE::CfgInfo::admin_base_url($cfg);
    $where = $adminbase . $where;
  }

  refresh_to($where);
}

1;
