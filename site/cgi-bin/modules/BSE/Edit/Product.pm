package BSE::Edit::Product;
use strict;
use base 'BSE::Edit::Article';
use Products;
use HTML::Entities;

my %money_fields =
  (
   retailPrice => "Retail price",
   wholesalePrice => "Wholesale price",
   gst => "GST",
  );

sub generator { 'Generate::Product' }

sub base_template_dirs {
  return ( "products" );
}

sub extra_templates {
  my ($self, $article) = @_;

  my @extras = $self->SUPER::extra_templates($article);
  my $basedir = $self->{cfg}->entry('paths', 'templates', $Constants::TMPLDIR);
  push @extras, 'shopitem.tmpl' if -f "$basedir/shopitem.tmpl";

  return @extras;
}

sub hash_tag {
  my ($article, $arg) = @_;

  my $value = $article->{$arg};
  defined $value or $value = '';
  if ($value =~ /\cJ/ && $value =~ /\cM/) {
    $value =~ tr/\cM//d;
  }

  return encode_entities($value);
}

sub low_edit_tags {
  my ($self, $acts, $req, $article, $articles, $msg, $errors) = @_;
 
  return 
    (
     product => [ \&hash_tag, $article ],
     $self->SUPER::low_edit_tags($acts, $req, $article, $articles, $msg,
				$errors),
     alloptions => join(",", sort keys %Constants::SHOP_PRODUCT_OPTS),
    );
}

sub edit_template { 
  my ($self, $article, $cgi) = @_;

  my $base = 'product';
  my $t = $cgi->param('_t');
  if ($t && $t =~ /^\w+$/) {
    $base = $t;
  }
  return $self->{cfg}->entry('admin templates', $base, 
			     "admin/edit_$base");
}

sub add_template { 
  my ($self, $article, $cgi) = @_;

  return $self->{cfg}->entry('admin templates', 'add_product', 
			     'admin/add_product');
}

sub validate_parent {
  my ($self, $data, $articles, $parent, $rmsg) = @_;

  my $shopid = $self->{cfg}->entryErr('articles', 'shop');
  unless ($parent && 
	  $parent->{generator} eq 'Generate::Catalog') {
    $$rmsg = "Products must be in a catalog (not $parent->{generator})";
    return;
  }

  return $self->SUPER::validate_parent($data, $articles, $parent, $rmsg);
}

sub _validate_common {
  my ($self, $data, $articles, $errors) = @_;

  for my $col (keys %money_fields) {
    my $value = $data->{$col};
    unless ($value =~ /^\d+(\.\d{1,2})?\s*/) {
      $errors->{$col} = "$money_fields{$col} invalid";
    }
  }

  my @bad_opts =grep !$Constants::SHOP_PRODUCT_OPTS{$_}, 
  split /,/, $data->{options};
  if (@bad_opts) {
    $errors->{options} = "Bad product options '". join(",", @bad_opts)."' entered";
  }

  return !keys %$errors;
}

sub validate {
  my ($self, $data, $articles, $rmsg, $errors) = @_;

  my $ok = $self->SUPER::validate($data, $articles, $rmsg, $errors);
  $self->_validate_common($data, $articles, $errors);

  for my $field (qw(title summary body)) {
    unless ($data->{$field} =~ /\S/) {
      $errors->{$field} = "No $field entered";
    }
  }

  return $ok && !keys %$errors;
}

sub validate_old {
  my ($self, $article, $data, $articles, $rmsg, $errors) = @_;

  $self->SUPER::validate($data, $articles, $rmsg, $errors)
    or return;
  
  return !keys %$errors;
}

sub possible_parents {
  my ($self, $article, $articles) = @_;

  my %labels;
  my @values;

  my $shopid = $self->{cfg}->entryErr('articles', 'shop');
  # the parents of a catalog can be other catalogs or the shop
  my $shop = $articles->getByPkey($shopid);
  my @work = [ $shopid, $shop->{title} ];
  while (@work) {
    my ($id, $title) = @{pop @work};
    push(@values, $id);
    $labels{$id} = $title;
    push @work, map [ $_->{id}, $title.' / '.$_->{title} ],
    sort { $b->{displayOrder} <=> $a->{displayOrder} }
      grep $_->{generator} eq 'Generate::Catalog', 
      $articles->getBy(parentid=>$id);
  }
  shift @values;
  delete $labels{$shopid};
  return (\@values, \%labels);
}

sub table_object {
  my ($self, $articles) = @_;

  'Products';
}

sub get_article {
  my ($self, $articles, $article) = @_;

  return Products->getByPkey($article->{id});
}

sub make_link {
  my ($self, $article) = @_;

  my $shop_uri = $self->{cfg}->entry('uri', 'shop', '/shop');
  my $urlbase = $self->{cfg}->entryVar('site', 'secureurl');
  return $urlbase.$shop_uri."/shop$article->{id}.html";
}

sub _fill_product_data {
  my ($self, $req, $data, $src) = @_;

  for my $money_col (qw(retailPrice wholesalePrice gst)) {
    if (exists $src->{$money_col}) {
      if ($src->{$money_col} =~ /^\d+(\.\d\d)?\s*/) {
	$data->{$money_col} = 100 * $src->{$money_col};
      }
      else {
	$data->{$money_col} = 0;
      }
    }
  }
  if (exists $src->{leadTime}) {
    $src->{leadTime} =~ /^\d+\s*$/
      or $src->{leadTime} = 0;
    $data->{leadTime} = $src->{leadTime};
  }
  if (exists $src->{summary} && length $src->{summary}) {
    if ($data->{id}) {
      if ($req->user_can('edit_field_edit_summary', $data)) {
	$data->{summary} = $src->{summary};
      }
    }
  }
}

sub fill_new_data {
  my ($self, $req, $data, $articles) = @_;

  $self->_fill_product_data($req, $data, $data);

  return $self->SUPER::fill_new_data($req, $data, $articles);
}

sub fill_old_data {
  my ($self, $req, $article, $src) = @_;

  $self->_fill_product_data($req, $article, $src);

  return $self->SUPER::fill_old_data($req, $article, $src);
}

sub default_template {
  my ($self, $article, $cfg, $templates) = @_;

  my $template = $cfg->entry('catalogs', 'template');
  return $template
    if $template && grep $_ eq $template, @$templates;

  return $self->SUPER::default_template($article, $cfg, $templates);
}

sub can_remove {
  my ($self, $req, $article, $articles, $rmsg) = @_;

  require OrderItems;
  my @items = OrderItems->getBy(productId=>$article->{id});
  if (@items) {
    $$rmsg = "There are orders for this product.  It cannot be deleted.";
    return;
  }

  return $self->SUPER::can_remove($req, $article, $articles, $rmsg);
}

1;
