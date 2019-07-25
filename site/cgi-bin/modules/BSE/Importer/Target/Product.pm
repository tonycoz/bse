package BSE::Importer::Target::Product;
use strict;
use base 'BSE::Importer::Target::Article';
use BSE::API qw(bse_make_product bse_make_catalog bse_add_image);
use BSE::TB::Articles;
use BSE::TB::Products;
use BSE::TB::ProductOptions;
use BSE::TB::ProductOptionValues;
use BSE::TB::PriceTiers;

our $VERSION = "1.011";

=head1 NAME

BSE::Importer::Target::Product - import target for products

=head1 SYNOPSIS

  [import profile foo]
  ...
  ; these are the defaults
  codes=0
  code_field=product_code
  parent=3
  ignore_missing=1
  reset_images=0
  reset_steps=0
  price_dollar=0
  prodopt_value_sep=|
  reset_prodopts=1

  # done by the importer
  my $target = BSE::Importer::Target::BSE::TB::Product->new
     (importer => $importer, opts => \%opts)
  ...
  $target->start($imp);
  # for each row:
  $target->row($imp, \%entry, \@parents);

=head1 DESCRIPTION

Provides a target for importing BSE products.

The import profile must provide C<title> and C<retailPrice> mappings.

=head1 CONFIGURATION

This is in addition to the configuration in
L<BSE::Importer::Target::Article/CONFIGURATION>.

=over

=item *

C<code_field> - the default changes to C<product_code>

=item *

C<parent> - the default changes to the id of the shop article.

=item *

C<price_dollar> - if true, the C<retailPrice> field and tier prices
are treated as dollar amounts rather than cents.  Default: 0.

=item *

C<prodopt_value_sep> - the separator between product options.
Default: C<|>.

=item *

C<reset_prodopts> - if true, product options are reset when updating a
product.  Default: 1.

=back

=head1 SPECIAL FIELDS

In addition to those in L<BSE::Importer::Target::Article/SPECIAL
FIELDS>, the following fields are used to import extra information
into products:

=over

=item *

C<< prodoptI<index>_name >> - define the name of a product option.
C<index> can be from 1 to 10.

=item *

C<< prodoptI<index>_values >> - define the values for a product
option, separated by the configured C<prodop_value_sep>.

=item *

C<< tier_price_I<tier_id> >> - set the product price for the specified
tier.

=back

=head1 METHODS

=over

=item new()

Create a new article import target.  Follows the protocol specified by
L<BSE::Importer::Target::Base>.

=cut

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
  unless ($importer->update_only) {
    defined $map->{retailPrice}
      or die "No retailPrice mapping found\n";
  }

  $self->{price_tiers} = +{ map { $_->id => $_ } BSE::TB::PriceTiers->all };

  return $self;
}

=item xform_entry()

Called by row() to perform an extra data transformation needed.

Currently this forces non-blank code fields if C<codes> is set,
removes the dollar sign if any from the retail prices, transforms the
retail price from dollars to cents if C<price_dollar> is configured
and warns if no price is set.

=cut

sub xform_entry {
  my ($self, $importer, $entry) = @_;

  $self->SUPER::xform_entry($importer, $entry);

  if (defined $entry->{product_code}) {
    $entry->{product_code} =~ s/\A\s+//;
    $entry->{product_code} =~ s/\s+\z//;
  }

  if ($self->{use_codes}) {
    $entry->{$self->{code_field}} =~ /\S/
      or die "$self->{code_field} blank with use_codes\n";
  }

  if (exists $entry->{retailPrice}) {
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
}

=item children_of()

Returns catalogs that are a child of the specified article.

sub children_of {
  my ($self, $parent) = @_;

  return grep $_->{generator} eq 'BSE::Generate::Catalog',
    BSE::TB::Articles->children($parent);
}

=item make_parent()

Create a catalog.

=cut

sub make_parent {
  my ($self, $importer, %entry) = @_;

  return bse_make_catalog(%entry);
}

=item find_leaf()

Find an existing product matching the code.

=cut

sub find_leaf {
  my ($self, $leaf_id, $importer) = @_;

  my $leaf;
  if ($self->{code_field} eq "id") {
    $leaf = BSE::TB::Products->getByPkey($leaf_id);
  }
  else {
    ($leaf) = BSE::TB::Products->getBy($self->{code_field}, $leaf_id)
      or return;
  }

  $importer->event(find_leaf => { id => $leaf_id, leaf => $leaf });

  if ($self->{reset_prodopts}) {
    my @options = $leaf->db_options;
    for my $option (@options) {
      $option->remove;
    }
  }

  return $leaf;
}

=item make_leaf()

Make a new product.

=cut

sub make_leaf {
  my ($self, $importer, %entry) = @_;

  my $leaf = bse_make_product(%entry);

  $importer->event(make_leaf => { leaf => $leaf });

  return $leaf;
}

=item fill_leaf()

Fill in the product with the new data.

=cut

sub fill_leaf {
  my ($self, $importer, $leaf, %entry) = @_;

  my $ordering = time;
  for my $opt_num (1 .. 10) {
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

  my %prices = map { $_->tier_id => $_->retailPrice } $leaf->prices;
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

=item default_parent()

Overrides the default parent.

=cut

sub default_parent { 3 }

=item default_code_field()

Overrides the default code field.

=cut

sub default_code_field { "product_code" }

=item key_fields

Fields that can act as key fields.

=cut

sub key_fields {
  my ($class) = @_;

  return ( $class->SUPER::key_fields(), "product_code" );
}

=item validate_make_leaf

=cut

sub validate_make_leaf {
  my ($self, $importer, $entry) = @_;

  if (defined $entry->{product_code} && $entry->{product_code} ne '') {
    my $other = BSE::TB::Products->getBy(product_code => $entry->{product_code});
    $other
      and die "Duplicate product_code with product ", $other->id, "\n";
  }
}

=item primary_key_fields

Fields we can't modify (or initialize) since the database (or database
interface) generates them.

=cut

sub primary_key_fields {
  my ($class) = @_;

  return ( $class->SUPER::primary_key_fields(), "articleId" );
}

1;

=back

=head1 AUTHOR

Tony Cook <tony@develop-help.com>

=cut
