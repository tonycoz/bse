package Generate::Catalog;

use strict;
use Generate;
use Products;
use base 'Generate::Article';
use Squirrel::Template;
use Constants qw($TMPLDIR $URLBASE %TEMPLATE_OPTS $CGI_URI $IMAGES_URI
                 $ADMIN_URI);
use Util qw(generate_button);

sub generate_low {
  my ($self, $template, $article, $articles, $embedded) = @_;

  my $products = Products->new;
  my @products = sort { $b->{displayOrder} <=> $a->{displayOrder} }
    grep $_->{listed} && $_->{parentid} == $article->{id}, $products->all;
  my $product_index = -1;
  my %acts;
  %acts =
    (
     $self->baseActs($articles, \%acts, $article, 0),
     article => sub { CGI::escapeHTML($article->{$_[0]}) },
     iterate_products =>
     sub {
       return ++$product_index < @products;
     },
     product=> sub { CGI::escapeHTML($products[$product_index]{$_[0]}) },
     admin => 
     sub { 
       if ($self->{admin}) {
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
<td><form action="$CGI_URI/admin/shopadmin.pl">
<input type=hidden name="add_product" value=1>
<input type=hidden name="parentid" value="$article->{id}">
<input type=submit value="Add product"></form></td>
<td><form action="$CGI_URI/admin/shopadmin.pl">
<input type=hidden name="product_list" value=1>
<input type=submit value="Full product list"></form></td>
HTML
	   if (generate_button()) {
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
	 return <<HTML;
 <a href="$CGI_URI/admin/move.pl?id=$products[$product_index]{id}&d=down"><img src="$IMAGES_URI/admin/move_down.gif" width="17" height="13" border="0" alt="Move Down" align="absbottom"></a>
HTML
       }
       else {
	 return '';
       }
     },
     moveUp=>
     sub {
       if ($self->{admin} && $product_index > 0) {
	 return <<HTML;
 <a href="$CGI_URI/admin/move.pl?id=$products[$product_index]{id}&d=up"><img src="$IMAGES_URI/admin/move_up.gif" width="17" height="13" border="0" alt="Move Up" align="absbottom"></a>
HTML
       }
       else {
	 return '';
       }
     },
    );
  my $oldurl = $acts{url};
  $acts{url} =
    sub {
      my $value = $oldurl->(@_);
      unless ($value =~ /^\w+:/) {
        # put in the base site url
        $value = $URLBASE . $value;
      }
      return $value;
    };

  return Squirrel::Template->new(%TEMPLATE_OPTS)
    ->replace_template($template, \%acts);
}

sub generate {
  my ($self, $article, $articles) = @_;

  open SOURCE, "< $TMPLDIR$article->{template}"
    or die "Cannot open template $article->{template}: $!";
  my $html = do { local $/; <SOURCE> };
  close SOURCE;

  $html =~ s/<:\s*embed\s+(?:start|end)\s*:>//g;
  
  return $self->generate_low($html, $article, $articles, 0);
}

sub embed {
  my ($self, $article, $articles, $template) = @_;

  $template = $article->{template}
    unless defined($template) && $template =~ /\S/;

  open SOURCE, "< $TMPLDIR$template"
    or die "Cannot open template $article->{template}: $!";
  my $html = do { local $/; <SOURCE> };
  close SOURCE;

  # the template will hopefully contain <:embed start:> and <:embed end:>
  # tags
  # otherwise pull out the body content
  if ($html =~ /<:\s*embed\s*start\s*:>(.*)<:\s*embed\s*end\s*:>/s
     || $html =~ m"<\s*body[^>]*>(.*)<\s*/\s*body>"s) {
    $html = $1;
  }

  return $self->generate_low($html, $article, $articles);
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

=item iterate ... products

Iterates over the products within this catalog.

=item product I<field>

The give attribute of the product.

=item admin

Generates administrative tools (in admin mode).

=back

=head1 BUGS

Still contains some code from before we derived from
Generate::Article, so there is some obsolete code still present.

=cut
