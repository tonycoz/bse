package BSE::ImportTargetProduct;
use strict;
use base 'BSE::ImportTargetArticle';
use BSE::API qw(bse_make_product bse_make_catalog bse_add_image);
use Articles;
use Products;

sub new {
  my ($class, %opts) = @_;

  my $self = $class->SUPER::new(%opts);

  my $importer = delete $opts{importer};

  $self->{price_dollar} = $importer->cfg_entry('price_dollar', 0);
  $self->{product_template} = $importer->cfg_entry('product_template');
  $self->{catalog_template} = $importer->cfg_entry('catalog_template');

  defined $map->{retailPrice}
    or die "No retailPrice mapping found\n";

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

  exists $entry{template}
    or $entry{template} = $importer->cfg_entry("catalog_template");

  return bse_make_catalog(%entry);
}

sub find_leaf {
  my ($self, $leaf_id) = @_;

  my ($leaf) = Products->getBy($self->{id_field}, $leaf_id)
    or return;

  return $leaf;
}

sub make_leaf {
  my ($self, $importer, %entry) = @_;

  exists $entry{template}
    or $entry{template} = $importer->cfg_entry("leaf_template");

  return bse_make_product(%entry);
}


sub xxrow {
  my ($self, $importer, $entry, $parents) = @_;

  defined $entry->{template}
    or $entry->{template} = $self->{product_template};

  $entry->{title} =~ /\S/
    or die "title blank\n";
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
  $entry->{title} =~ /\n/
    and die "Title may not contain newlines";
  $entry->{summary}
    or $entry->{summary} = $entry->{title};
  $entry->{description}
    or $entry->{description} = $entry->{title};
  $entry->{body}
    or $entry->{body} = $entry->{title};
  
  $entry->{parentid} = $self->_find_parent($importer, $self->{parent}, @$parents);
  my $product;
  if ($self->{use_codes}) {
    $product = Products->getBy(product_code => $entry->{product_code});
  }
  if ($product) {
    @{$product}{keys %$entry} = values %$entry;
    $product->save;
    $importer->info("Updated $product->{id}: $entry->{title}");
    if ($self->{reset_images}) {
      $product->remove_images($importer->cfg);
      $importer->info(" $product->{id}: Reset images");
    }
  }
  else {
    $product = bse_make_product
      (
       cfg => $self->{cfg},
       %$entry
      );
    $importer->info("Added $product->{id}: $entry->{title}");
  }
  for my $image_index (1 .. 10) {
    my $file = $entry->{"image${image_index}_file"};
    $file
      or next;
    my $full_file = $importer->find_file($file);
    $full_file
      or die "File '$file' not found for image$image_index\n";
    
    my %opts = ( file => $full_file );
    for my $key (qw/alt name url storage/) {
      my $fkey = "image${image_index}_$key";
      $entry->{$fkey}
	and $opts{$key} = $entry->{$fkey};
    }
    
    my %errors;
    my $im = bse_add_image($self->{cfg}, $product, %opts, 
			   errors => \%errors);
    $im 
      or die join(", ",map "$_: $errors{$_}", keys %errors), "\n";
    $importer->info(" $product->{id}: Add image '$file'");
  }
  push @{$self->{leaves}}, $product;
}

sub xx_find_parent {
  my ($self, $importer, $parent, @parents) = @_;

  @parents
    or return $parent;
  my $cache = $self->{parent_cache};
  unless ($cache->{$parent}) {
    my @kids = grep $_->{generator} eq 'Generate::Catalog', 
      Articles->children($parent);
    $cache->{$parent} = \@kids;
  }

  my $title = shift @parents;
  my ($cat) = grep lc $_->{title} eq lc $title, @{$cache->{$parent}};
  unless ($cat) {
    my %opts =
      (
       cfg => $self->{cfg},
       parentid => $parent,
       title => $title,
       body => $title,
      );
    $self->{catalog_template}
      and $opts{template} = $self->{catalog_template};
    $cat = bse_make_catalog(%opts);
    $importer->info("Add catalog $cat->{id}: $title");
    push @{$cache->{$parent}}, $cat;
  }

  unless ($self->{catseen}{$cat->{id}}) {
    $self->{catseen}{$cat->{id}} = 1;
    push @{$self->{catalogs}}, $cat;
  }

  return $self->_find_parent($importer, $cat->{id}, @parents);
}

sub default_parent { 3 }

sub default_code_field { "product_code" }

1;
