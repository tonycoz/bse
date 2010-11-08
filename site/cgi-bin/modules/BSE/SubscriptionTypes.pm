package BSE::SubscriptionTypes;
use strict;
use Squirrel::Table;
use vars qw(@ISA $VERSION);
@ISA = qw(Squirrel::Table);
use BSE::SubscriptionType;

our $VERSION = "1.000";

sub rowClass {
  return 'BSE::SubscriptionType';
}

sub filters {
  my ($class, $cfg) = @_;

  local @INC = @INC;

  my $local_inc = $cfg->entry('paths', 'libraries');
  unshift @INC, $local_inc if $local_inc;

  my @filters;

  for my $index (1..10) {
    my $entry = $cfg->entry('newsletter filters', "criteria$index");
    $entry or last;

    my ($load_class, $data) = split /;/, $entry, 2;
    (my $file = $load_class . ".pm") =~ s!::!/!g;

    require $file;
    
    my $filter = $load_class->new(cfg=>$cfg, data => $data, index => $index);
    push @filters, $filter;
  }

  @filters;
}

1;
