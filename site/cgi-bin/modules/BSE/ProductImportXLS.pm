package BSE::ProductImportXLS;
use strict;
use Spreadsheet::ParseExcel;
use BSE::API qw(bse_make_product bse_make_catalog);
use Articles;
use Products;

sub new {
  my ($class, $cfg, $profile) = @_;

  # field mapping
  my $section = "xls import $profile";
  my %ids = $cfg->entriesCS($section);
  keys %ids
    or die "No entries found for profile $profile\n";
  
  my $sheet = $cfg->entry($section, "sheet", 1);
  my $skiprows = $cfg->entry($section, 'skiprows', 1);
  my $use_codes = $cfg->entry($section, 'codes', 0);
  my $parent = $cfg->entry($section, 'parent', 3);
  my $price_dollar = $cfg->entry($section, 'price_dollar', 0);

  my %map;
  for my $map (grep /^map_\w+$/, keys %ids) {
    (my $out = $map) =~ s/^map_//;
    my $in = $ids{$map};
    $in =~ /^\d+$/
      or die "Mapping for $out not numeric\n";
    $map{$out} = $in;
  }
  my %xform;
  for my $xform (grep /^xform_\w+$/, keys %ids) {
    (my $out = $xform) =~ s/^xform_//;
    $map{$out}
      or die "Xform for $out but no mapping\n";
    my $code = "sub { local (\$_) = \@_; \n".$ids{$xform}."\n; return \$_ }";
    my $sub = eval $code;
    $sub
      or die "Compilation error for $xform code: $@\n";
    $xform{$out} = $sub;
  }
  defined $map{title}
    or die "No title mapping found\n";
  defined $map{retailPrice}
    or die "No retailPrice mapping found\n";
  if ($use_codes && !defined $map{product_code}) {
    die "No product_code mapping found with 'codes' enabled\n";
  }
  my @cats;
  for my $cat (qw/cat1 cat2 cat3/) {
    my $col = $ids{$cat};
    $col and push @cats, $col;
  }

  return bless 
    {
     map => \%map,
     xform => \%xform,
     sheet => $sheet,
     skiprows => $skiprows,
     codes => $use_codes,
     cats => \@cats,
     parent => $parent,
     price_dollar => $price_dollar,
     cfg => $cfg,
     product_template => scalar($cfg->entry($section, 'product_template')),
     catalog_template => scalar($cfg->entry($section, 'catalog_template')),
    }, $class;
}

sub profiles {
  my ($class, $cfg) = @_;

  my %ids = $cfg->entries("xls product imports");
  return \%ids;
}

sub process {
  my ($self, $filename, $callback) = @_;

  $self->{catseen} = {};
  $self->{catalogs} = [];
  $self->{products} = [];
  my $parser = Spreadsheet::ParseExcel->new;
  my $wb = $parser->Parse($filename)
    or die "Could not parse $filename";
  $self->{sheet} <= $wb->{SheetCount}
    or die "No enough worksheets in input\n";
  my $ws = ($wb->worksheets)[$self->{sheet}-1]
    or die "No worksheet found at $self->{sheet}\n";

  my ($minrow, $maxrow) = $ws->RowRange;
  my @errors;
  my %cat_cache;
  for my $rownum ($self->{skiprows} ... $maxrow) {
    eval {
      my %entry;

      $self->{product_template}
	and $entry{template} = $self->{product_template};

      # load from mapping
      for my $col (keys %{$self->{map}}) {
	my $cell = $ws->get_cell($rownum, $self->{map}{$col}-1);
	$entry{$col} = $cell->value;

	if ($self->{xform}{$col}) {
	  $entry{$col} = $self->{xform}{$col}->($entry{$col});
	}
      }
      $entry{title} =~ /\S/
	or die "title blank\n";
      if ($self->{codes}) {
	$entry{product_code} =~ /\S/
	  or die "product_code blank with use_codes\n";
      }
      $entry{retailPrice} =~ s/\$//; # in case

      $self->{price_dollar}
	and $entry{retailPrice} *= 100;

      $entry{summary}
	or $entry{summary} = $entry{title};
      $entry{description}
	or $entry{description} = $entry{title};
      $entry{body}
	or $entry{body} = $entry{title};

      my @cats;
      for my $cat (@{$self->{cats}}) {
	my $cell = $ws->get_cell($rownum, $cat-1);
	my $value = $cell->value;
	defined $value && $value =~ /\S/
	  and push @cats, $value;
      }
      $entry{parentid} = $self->_find_cat(\%cat_cache, $callback, $self->{parent}, @cats);
      my $product;
      if ($self->{codes}) {
	$product = Products->getBy(product_code => $entry{product_code});
      }
      if ($product) {
	@{$product}{keys %entry} = values %entry;
	$product->save;
	$callback
	  and $callback->("Updated $product->{id}: $entry{title}");
      }
      else
      {
	$product = bse_make_product
	  (
	   cfg => $self->{cfg},
	   %entry
	  );
	$callback
	  and $callback->("Added $product->{id}: $entry{title}");
      }
      push @{$self->{products}}, $product;
    };
    if ($@) {
      my $error = "Row ".($rownum+1).": $@";
      $error =~ s/\n\z//;
      $error =~ tr/\n/ /s;
      push @{$self->{errors}}, $error;
      $callback
	and $callback->("Error: $error");
    }
  }
}

sub _find_cat {
  my ($self, $cache, $callback, $parent, @cats) = @_;

  @cats
    or return $parent;
  unless ($cache->{$parent}) {
    my @kids = grep $_->{generator} eq 'Generate::Catalog', 
      Articles->children($parent);
    $cache->{$parent} = \@kids;
  }

  my $title = shift @cats;
  my ($cat) = grep $_->{title} eq $title, @{$cache->{$parent}};
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
    $callback
      and $callback->("Add catalog $cat->{id}: $title");
    push @{$cache->{$parent}}, $cat;
  }

  unless ($self->{catseen}{$cat->{id}}) {
    $self->{catseen}{$cat->{id}} = 1;
    push @{$self->{catalogs}}, $cat;
  }

  return $self->_find_cat($cache, $callback, $cat->{id}, @cats);
}

sub errors {
  $_[0]{errors}
    and return @{$_[0]{errors}};

  return;
}

sub products {
  $_[0]{products}
    and return @{$_[0]{products}};

  return;
}

sub catalogs {
  $_[0]{catalogs} or return;

  return @{$_[0]{catalogs}};
}

1;
