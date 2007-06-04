package BSE::Report;
use strict;

use base 'DevHelp::Report';

sub new {
  my ($class, $req_or_cfg) = @_;

  my ($cfg, $req);
  if ($req_or_cfg->isa('BSE::Cfg')) {
    $cfg = $req_or_cfg;
  }
  else {
    $cfg = $req_or_cfg->cfg;
    $req = $req_or_cfg;
  }
  
  my $work = $class->SUPER::new($cfg, 'reports');
  $req and $work->{req} = $req;

  return $work;
}

sub list_reports {
  my ($self) = @_;

  if ($self->{req}) {
    my %entries = $self->SUPER::list_reports;
    my @delete;
    for my $key (keys %entries) {
      $self->report_accessible($key) or push @delete, $key;
    }
    delete @entries{@delete};
    return %entries;
  }
  else {
    return;
  }
}

sub report_accessible {
  my ($self, $report) = @_;

  $self->{req} or return;

  my $rights = $self->report_entry($report, 'bse_rights');
  defined $rights or $rights = '';
  $rights =~ tr/ //d;
  $rights eq '' and return 1; # no controls
  for my $set (split /\|/, $rights) {
    grep $self->{req}->user_can($_, -1), split /[,;]/, $set
      and return 1;
  }

  return;
}

sub url_show_args {
  s_show => 1
}

1;
