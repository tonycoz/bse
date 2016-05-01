package BSE::TB::Coupons;
use strict;
use Squirrel::Table;
our @ISA = qw(Squirrel::Table);
use BSE::TB::Coupon;

our $VERSION = "1.002";

sub rowClass {
  return 'BSE::TB::Coupon';
}

sub make {
  my ($self, %opts) = @_;

  my $tiers = delete $opts{tiers};

  my $config_obj = delete $opts{config_obj};
  if ($config_obj) {
    $opts{discount_percent} = delete $config_obj->{discount_percent};
    require JSON;
    $opts{config} = JSON->new->encode($config_obj);
  }

  my $coupon = $self->SUPER::make(%opts);

  if ($tiers) {
    $coupon->set_tiers($tiers);
    $coupon->save;
  }

  return $coupon;
}

=item behaviour_class

Return the class name of a behaviour class given a class id.

Loads the class.

Throws an exception if no class if configured for the class id or if
the class cannot be loaded.

=cut

sub behaviour_class {
  my ($class, $classid) = @_;

  my $bclass = BSE::Cfg->single->entryErr("coupon classes", $classid);
  (my $bfile = $bclass . ".pm") =~ s(::)(/)g;

  require $bfile;

  return $bclass;
}

=item behaviour_classes

Returns a hash of all behaviour classes with the keys being the
classid and the value the class name.

=cut

sub behaviour_classes {
  my ($class) = @_;

  my %entries = BSE::Cfg->single->entries("coupon classes");
  my %bclasses;
  for my $classid (keys %entries) {
    $bclasses{$classid} = $class->behaviour_class($classid);
  }

  \%bclasses;
}

1;
