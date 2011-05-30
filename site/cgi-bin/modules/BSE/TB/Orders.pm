package BSE::TB::Orders;
use strict;
use Squirrel::Table;
use vars qw(@ISA $VERSION);
@ISA = qw(Squirrel::Table);
use BSE::TB::Order;

our $VERSION = "1.002";

sub rowClass {
  return 'BSE::TB::Order';
}

# shipping methods when we don't automate shipping
sub dummy_shipping_methods {
  my $cfg = BSE::Cfg->single;

  my %ship = $cfg->entriesCS("dummy shipping methods");
  my @ship;
  for my $key (sort { $ship{$a} cmp $ship{$b} } keys %ship) {
    my $name = $key;
    $ship{$key} =~ /,(.*)/ and $name = $1;

    push @ship, { id => $key, name => $name };
  }

  unshift @ship,
    {
     id => "",
     name => "(None selected)",
    };

  return @ship;
}

1;
