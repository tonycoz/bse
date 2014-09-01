package BSE::ProductImportXLS;
use strict;
use Spreadsheet::ParseExcel;
use BSE::API qw(bse_make_product bse_make_catalog bse_add_image);
use BSE::TB::Articles;
use BSE::TB::Products;
use Config;

our $VERSION = "1.003";

sub new {
  my ($class, $cfg, $profile, %opts) = @_;

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
  my $reset_images = $cfg->entry($section, 'reset_images', 0);
  my $file_path = $cfg->entry($section, 'file_path');
  defined $file_path or $file_path = '';
  my @file_path = split /$Config{path_sep}/, $file_path;
  if ($opts{file_path}) {
    unshift @file_path, 
      map 
	{ 
	  split /$Config{path_sep}/, $_ 
	}
	  @{$opts{file_path}};
  }

  my %map;
  for my $map (grep /^map_\w+$/, keys %ids) {
    (my $out = $map) =~ s/^map_//;
    my $in = $ids{$map};
    $in =~ /^\d+$/
      or die "Mapping for $out not numeric\n";
    $map{$out} = $in;
  }
  my %set;
  for my $set (grep /^set_\w+$/, keys %ids) {
    (my $out = $set) =~ s/^set_//;
    $set{$out} = $ids{$set};
  }
  my %xform;
  for my $xform (grep /^xform_\w+$/, keys %ids) {
    (my $out = $xform) =~ s/^xform_//;
    $map{$out}
      or die "Xform for $out but no mapping\n";
    my $code = "sub { (local \$_, my \$product) = \@_; \n".$ids{$xform}."\n; return \$_ }";
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
     set => \%set,
     sheet => $sheet,
     skiprows => $skiprows,
     codes => $use_codes,
     cats => \@cats,
     parent => $parent,
     price_dollar => $price_dollar,
     reset_images => $reset_images,
     cfg => $cfg,
     file_path => \@file_path,
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
      my %entry = %{$self->{set}};

      $self->{product_template}
	and $entry{template} = $self->{product_template};

      # load from mapping
      my $non_blank = 0;
      for my $col (keys %{$self->{map}}) {
	my $cell = $ws->get_cell($rownum, $self->{map}{$col}-1);
	if (defined $cell) {
	  $entry{$col} = $cell->value;
	}
	else {
	  $entry{$col} = '';
	}
	$non_blank ||= $entry{$col} =~ /\S/;
      }
      $non_blank
	or return;
      for my $col (keys %{$self->{xform}}) {
	$entry{$col} = $self->{xform}{$col}->($entry{$col}, \%entry);
      }
      $entry{title} =~ /\S/
	or die "title blank\n";
      if ($self->{codes}) {
	$entry{product_code} =~ /\S/
	  or die "product_code blank with use_codes\n";
      }
      $entry{retailPrice} =~ s/\$//; # in case

      if ($entry{retailPrice} =~ /\d/) {
	$self->{price_dollar}
	  and $entry{retailPrice} *= 100;
      }
      else {
	$callback
	  and $callback->("Row $rownum: Warning: no price");
	$entry{retailPrice} = 0;
      }
      $entry{title} =~ /\n/
	and die "Title may not contain newlines";
      $entry{summary}
	or $entry{summary} = $entry{title};
      $entry{description}
	or $entry{description} = $entry{title};
      $entry{body}
	or $entry{body} = $entry{title};

      my @cats;
      for my $cat (@{$self->{cats}}) {
	my $cell = $ws->get_cell($rownum, $cat-1);
	my $value;
	defined $cell and
	  $value = $cell->value;
	defined $value && $value =~ /\S/
	  and push @cats, $value;
      }
      $entry{parentid} = $self->_find_cat(\%cat_cache, $callback, $self->{parent}, @cats);
      my $product;
      if ($self->{codes}) {
	$product = BSE::TB::Products->getBy(product_code => $entry{product_code});
      }
      if ($product) {
	@{$product}{keys %entry} = values %entry;
	$product->save;
	$callback
	  and $callback->("Updated $product->{id}: $entry{title}");
	if ($self->{reset_images}) {
	  $product->remove_images($self->{cfg});
	  $callback
	    and $callback->(" $product->{id}: Reset images");
	}
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
      for my $image_index (1 .. 10) {
	my $file = $entry{"image${image_index}_file"};
	$file
	  or next;
	my $full_file = $self->_find_file($file);
	$full_file
	  or die "File '$file' not found for image$image_index\n";

	my %opts = ( file => $full_file );
	for my $key (qw/alt name url storage/) {
	  my $fkey = "image${image_index}_$key";
	  $entry{$fkey}
	    and $opts{$key} = $entry{$fkey};
	}

	my %errors;
	my $im = bse_add_image($self->{cfg}, $product, %opts, 
			       errors => \%errors);
	$im 
	  or die join(", ",map "$_: $errors{$_}", keys %errors), "\n";
	$callback
	  and $callback->(" $product->{id}: Add image '$file'");
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
    my @kids = grep $_->{generator} eq 'BSE::Generate::Catalog', 
      BSE::TB::Articles->children($parent);
    $cache->{$parent} = \@kids;
  }

  my $title = shift @cats;
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

sub _find_file {
  my ($self, $file) = @_;

  for my $path (@{$self->{file_path}}) {
    my $full = "$path/$file";
    -f $full and return $full;
  }

  return;
}

1;
