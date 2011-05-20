package Products;
use strict;
use Squirrel::Table;
use vars qw(@ISA $VERSION);
@ISA = qw(Squirrel::Table);
use Product;

our $VERSION = "1.001";

sub rowClass {
  return 'Product';
}

sub all_visible_children {
  my ($self, $id) = @_;

  require OtherParents;
  my @normal_prods = Products->visible_children($id);
  my @step_prods = Products->visible_step_children($id);
  
  my %order =
    (
     ( map { $_->{id} => $_->{displayOrder} } @normal_prods ),
     ( map 
       { 
	 $_->{childId} => $_->{parentDisplayOrder}
       } OtherParents->getBy(parentId => $id)
     )
    );

  my %kids = map { $_->{id} => $_ } @step_prods, @normal_prods;

  return @kids{ sort { $order{$b} <=> $order{$a} } keys %kids };
}

sub visible_children {
  my ($class, $id) = @_;

  use BSE::Util::SQL qw/now_sqldate/;
  my $today = now_sqldate();
  
  return Products->getSpecial(visible_children_of => $id, $today);
}

sub visible_step_children {
  my ($class, $id) = @_;

  use BSE::Util::SQL qw/now_sqldate/;
  my $today = now_sqldate();
  
  return Products->getSpecial(visibleStep => $id, $today);
}

{
  my $tiers;
  sub pricing_tiers {
    unless ($tiers) {
      require BSE::TB::PriceTiers;
      $tiers = [ sort { $a->display_order <=> $b->display_order }
		 BSE::TB::PriceTiers->all ];
    }

    return @$tiers;
  }
}

1;
