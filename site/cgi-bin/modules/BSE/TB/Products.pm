package BSE::TB::Products;
use strict;
use Squirrel::Table;
use vars qw(@ISA $VERSION);
@ISA = qw(Squirrel::Table BSE::TB::TagOwners);
use BSE::TB::Product;

our $VERSION = "1.004";

sub rowClass {
  return 'BSE::TB::Product';
}

sub all_visible_children {
  my ($self, $id) = @_;

  require OtherParents;
  my @normal_prods = BSE::TB::Products->visible_children($id);
  my @step_prods = BSE::TB::Products->visible_step_children($id);
  
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

sub all_visible_product_tags {
  my ($self, $id) = @_;

  require BSE::TB::Tags;
  require BSE::TB::TagMembers;
  return
    {
     tags => [ BSE::TB::Tags->getSpecial(allprods => $id, $id) ],
     members => [ BSE::TB::TagMembers->getSpecial(allprods => $id, $id) ],
    };
}

*all_visible_products = \&all_visible_children;

sub visible_children {
  my ($class, $id) = @_;

  use BSE::Util::SQL qw/now_sqldate/;
  my $today = now_sqldate();
  
  return BSE::TB::Products->getSpecial(visible_children_of => $id, $today);
}

sub visible_step_children {
  my ($class, $id) = @_;

  use BSE::Util::SQL qw/now_sqldate/;
  my $today = now_sqldate();
  
  return BSE::TB::Products->getSpecial(visibleStep => $id, $today);
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
