package Generate::Catalog;

use strict;
use Generate;
use Products;
use base 'Generate::Article';
use BSE::Template;
use Constants qw($CGI_URI $IMAGES_URI $ADMIN_URI);
use Util qw(generate_button);
use OtherParents;
use DevHelp::HTML;

sub generate_low {
  my ($self, $template, $article, $articles, $embedded) = @_;

  my $products = Products->new;
  my @products = sort { $b->{displayOrder} <=> $a->{displayOrder} }
    grep $_->{listed} && $_->{parentid} == $article->{id}, $products->all;
  my $product_index = -1;
  my @subcats = sort { $b->{displayOrder} <=> $a->{displayOrder} }
    grep $_->{listed} && UNIVERSAL::isa($_->{generator}, 'Generate::Catalog'),
    $articles->getBy(parentid => $article->{id});
  my $other_parents = OtherParents->new;
  my ($year, $month, $day) = (localtime)[5,4,3];
  my $today = sprintf("%04d-%02d-%02d 00:00:00ZZZ", $year+1900, $month+1, $day);
  my @stepprods = $article->visible_stepkids;
  my $stepprod_index;
  my @allprods = $article->all_visible_kids;
  require 'Generate/Product.pm';
  @allprods = grep UNIVERSAL::isa($_->{generator}, 'Generate::Product'), @allprods;
  for (@allprods) {
    unless ($_->isa('Product')) {
      $_ = Products->getByPkey($_->{id});
    }
  }
  my $allprod_index;
  my $category_index = -1;
  my %acts;
  %acts =
    (
     $self->baseActs($articles, \%acts, $article, $embedded),
     article => sub { escape_html($article->{$_[0]}) },
     iterate_products =>
     sub {
       return ++$product_index < @products;
     },
     product=> sub { escape_html($products[$product_index]{$_[0]}) },
     ifProducts => sub { @products },
     admin => 
     sub { 
       if ($self->{admin} && $self->{request}) {
	 my $req = $self->{request};
	 my $html = <<HTML;
<table>
<tr>
<td><form action="$CGI_URI/admin/add.pl">
<input type=submit value="Edit Catalog">
<input type=hidden name=id value="$article->{id}">
</form></td>
<td><form action="$ADMIN_URI">
<input type=submit value="Admin menu">
</form></td>
HTML
	 if ($req->user_can('edit_add_child', $article)) {
	   $html .= <<HTML;
<td><form action="$CGI_URI/admin/add.pl">
<input type=hidden name="parentid" value="$article->{id}">
<input type=hidden name="type" value="Product">
<input type=submit value="Add product"></form></td>
<td><form action="$CGI_URI/admin/add.pl">
<input type=hidden name="parentid" value="$article->{id}">
<input type=hidden name="type" value="Catalog">
<input type=submit value="Add Sub-catalog"></form></td>
HTML
         }
	 $html .= <<HTML;
<td><form action="$CGI_URI/admin/shopadmin.pl">
<input type=hidden name="product_list" value=1>
<input type=submit value="Full product list"></form></td>
HTML
	 if (generate_button()
	     && $req->user_can(regen_article=>$article)) {
	   $html .= <<HTML;
<td><form action="$CGI_URI/admin/generate.pl">
<input type=hidden name=id value="$article->{id}">
<input type=submit value="Regenerate">
</form></td>
HTML
	 }
	 $html .= <<HTML;
<td><form action="$CGI_URI/admin/admin.pl" target="_blank">
<input type=submit value="Display">
<input type=hidden name=id value="$article->{id}">
<input type=hidden name=admin value="0"></form></td>
</tr></table>
HTML
	 return $html;
       }
       else {
	 return '';
       }
     },
     # for rearranging order in admin mode
     moveDown=>
     sub {
       if ($self->{admin} && $product_index < $#products) {
	 my $html = <<HTML;
 <a href="$CGI_URI/admin/move.pl?id=$products[$product_index]{id}&d=down"><img src="$IMAGES_URI/admin/move_down.gif" width="17" height="13" border="0" alt="Move Down" align="absbottom" /></a>
HTML
	 chop $html;
	 return $html;
       }
       else {
	 return '';
       }
     },
     moveUp=>
     sub {
       if ($self->{admin} && $product_index > 0) {
	 my $html = <<HTML;
 <a href="$CGI_URI/admin/move.pl?id=$products[$product_index]{id}&d=up"><img src="$IMAGES_URI/admin/move_up.gif" width="17" height="13" border="0" alt="Move Up" align="absbottom" /></a>
HTML
	 chop $html;
	 return $html;
       }
       else {
	 return '';
       }
     },
     iterate_allprods_reset => sub { $allprod_index = -1 },
     iterate_allprods => sub { ++$allprod_index < @allprods },
     allprod => sub { escape_html($allprods[$allprod_index]{$_[0]}) },
     moveallprod =>
     sub {
       my ($arg, $acts, $funcname, $templater) = @_;

       return '' unless $self->{admin};
       return '' unless $self->{request};
       return '' 
	 unless $self->{request}->user_can(edit_reorder_children => $article);
       return '' unless @allprods > 1;

       my ($img_prefix, $urladd) = 
	 DevHelp::Tags->get_parms($arg, $acts, $templater);
       $img_prefix = '' unless defined $img_prefix;
       $urladd = '' unless defined $urladd;

       my $html = '';
       my $can_move_up = $allprod_index > 0;
       my $can_move_down = $allprod_index < $#allprods;
       return '' unless $can_move_up || $can_move_down;
       my $blank = '<img src="/images/trans_pixel.gif" width="17" height="13" border="0" alt="" align="absbotton" />';
       my $myid = $allprods[$allprod_index]{id};
       my $refreshto = "$CGI_URI/admin/admin.pl?id=$article->{id}$urladd";
       if ($can_move_down) {
	 my $nextid = $allprods[$allprod_index+1]{id};
	 $html .= <<HTML;
<a href="$CGI_URI/admin/move.pl?stepparent=$article->{id}&d=swap&id=$myid&other=$nextid&refreshto=$refreshto"><img src="$IMAGES_URI/admin/${img_prefix}move_down.gif" width="17" height="13" border="0" alt="Move Down" align="absbottom" /></a>
HTML
       }
       else {
	 $html .= $blank;
       }
       if ($can_move_up) {
	 my $previd = $allprods[$allprod_index-1]{id};
	 $html .= <<HTML;
<a href="$CGI_URI/admin/move.pl?stepparent=$article->{id}&d=swap&id=$myid&other=$previd&refreshto=$refreshto"><img src="$IMAGES_URI/admin/${img_prefix}move_up.gif" width="17" height="13" border="0" alt="Move Up" align="absbottom" /></a>
HTML
       }
       else {
	 $html .= $blank;
       }
       $html =~ tr/\n//d;
       return $html;
     },
     ifAnyProds => sub { escape_html(@allprods) },
     iterate_stepprods_reset => sub { $stepprod_index = -1 },
     iterate_stepprods => sub { ++$stepprod_index < @stepprods; },
     stepprod => sub { escape_html($stepprods[$stepprod_index]{$_[0]}) },
     ifStepProds => sub { @stepprods },
     iterate_catalogs_reset => sub { $category_index = -1 },
     iterate_catalogs => sub { ++$category_index < @subcats },
     catalog => 
     sub { escape_html($subcats[$category_index]{$_[0]}) },
     ifSubcats => sub { @subcats },
    );
  my $oldurl = $acts{url};
  my $urlbase = $self->{cfg}->entryVar('site', 'url');
  $acts{url} =
    sub {
      my $value = $oldurl->(@_);
      unless ($value =~ /^\w+:/) {
        # put in the base site url
        $value = $urlbase . $value;
      }
      return $value;
    };

  return BSE::Template->replace($template, $self->{cfg}, \%acts);
}

sub generate {
  my ($self, $article, $articles) = @_;

  my $html = BSE::Template->get_source($article->{template}, $self->{cfg});

  $html =~ s/<:\s*embed\s+(?:start|end)\s*:>//g;
  
  return $self->generate_low($html, $article, $articles, 0);
}

1;

__END__

=head1 NAME

  Generate::Catalog - page generator class for catalog pages

=head1 DESCRIPTION

  This class is used to generate catalog pages for BSE.  It derives
  from L<Generate::Article>, and inherits it's tags.

=head1 TAGS

=over 4

=item iterator ... products

Iterates over the products within this catalog.

=item product I<field>

The given attribute of the product.

=item ifProducts

Conditional tag, true if there are any normal child products.

=item iterator ... allprods

Iterates over the products and step products of this catalog, setting
the allprod tag for each item.

=item allprod I<field>

The given attribute of the product.

=item ifAnyProds

Conditional tag, true if there are any normal or step products.

=item iterator ... stepprods

Iterates over any step products of this catalog, setting the
I<stepprod> tag to the current step product.  Does not iterate over
normal child products.

=item stepprod I<field>

The given attribute of the current step product.

=item ifStepProds

Conditional tag, true if there are any step products.

=item iterator ... catalogs

Iterates over any sub-catalogs.

=item catalog I<field>

The given field of the current catalog.

=item ifSubcats

Conditional tag, true if there are any subcatalogs.

=item admin

Generates administrative tools (in admin mode).

=back

=head1 BUGS

Still contains some code from before we derived from
Generate::Article, so there is some obsolete code still present.

=cut
