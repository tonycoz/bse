package BSE::ImportTargetProduct;
use strict;
use base 'BSE::ImportTargetArticle';
use BSE::API qw(bse_make_product bse_make_catalog bse_add_image);
use Articles;
use Products;
use BSE::TB::ProductOptions;
use BSE::TB::ProductOptionValues;
use BSE::TB::PriceTiers;

our $VERSION = "1.001";

sub new {
  my ($class, %opts) = @_;

  my $self = $class->SUPER::new(%opts);

  my $importer = delete $opts{importer};

  $self->{price_dollar} = $importer->cfg_entry('price_dollar', 0);
  $self->{product_template} = $importer->cfg_entry('product_template');
  $self->{catalog_template} = $importer->cfg_entry('catalog_template');
  $self->{prodopt_value_sep} = $importer->cfg_entry("prodopt_separator", "|");
  $self->{reset_prodopts} = $importer->cfg_entry("reset_prodopts", 1);

  my $map = $importer->maps;
  defined $map->{retailPrice}
    or die "No retailPrice mapping found\n";

  $self->{price_tiers} = +{ map { $_->id => $_ } BSE::TB::PriceTiers->all };

  return $self;
}

sub xform_entry {
  my ($self, $importer, $entry) = @_;

  $self->SUPER::xform_entry($importer, $entry);

  if ($self->{use_codes}) {
    $entry->{product_code} =~ /\S/
      or die "product_code blank with use_codes\n";
  }
  $entry->{retailPrice} =~ s/\$//; # in case

  if ($entry->{retailPrice} =~ /\d/) {
    $self->{price_dollar}
      and $entry->{retailPrice} *= 100;
  }
  else {
    $importer->warn("Warning: no price");
    $entry->{retailPrice} = 0;
  }
}

sub children_of {
  my ($self, $parent) = @_;

  return grep $_->{generator} eq 'Generate::Catalog',
    Articles->children($parent);
}

sub make_parent {
  my ($self, $importer, %entry) = @_;

  return bse_make_catalog(%entry);
}

sub find_leaf {
  my ($self, $leaf_id) = @_;

  my ($leaf) = Products->getBy($self->{code_field}, $leaf_id)
    or return;

  if ($self->{reset_prodopts}) {
    my @options = $leaf->db_options;
    for my $option (@options) {
      $option->remove;
    }
  }

  return $leaf;
}

sub make_leaf {
  my ($self, $importer, %entry) = @_;

  return bse_make_product(%entry);
}

sub fill_leaf {
  my ($self, $importer, $leaf, %entry) = @_;

  my $ordering = time;
  for my $opt_num (1 .. 5) {
    my $name = $entry{"prodopt${opt_num}_name"};
    my $values = $entry{"prodopt${opt_num}_values"};

    defined $name && $name =~ /\S/ && $values =~ /\S/
      or next;
    my @values = split /\Q$self->{prodopt_value_sep}/, $values
      or next;

    my $option = BSE::TB::ProductOptions->make
      (
       product_id => $leaf->id,
       name => $name,
       display_order => $ordering++,
      );

    for my $value (@values) {
      my $entry = BSE::TB::ProductOptionValues->make
	(
	 product_option_id => $option->id,
	 value => $value,
	 display_order => $ordering++,
	);
    }
  }

  my %prices;
  for my $tier_id (keys %{$self->{price_tiers}}) {
    my $price = $entry{"tier_price_$tier_id"};
    if (defined $price && $price =~ /\d/) {
      $price =~ s/\$//; # in case
      $price *= 100 if $self->{price_dollar};

      $prices{$tier_id} = $price;
    }
  }

  $leaf->set_prices(\%prices);

  return $self->SUPER::fill_leaf($importer, $leaf, %entry);
}

sub default_parent { 3 }

sub default_code_field { "product_code" }

1;
