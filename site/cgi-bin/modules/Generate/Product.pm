package Generate::Product;
use strict;
use Generate::Article;
use Products;
use Images;
use base qw(Generate::Article);
use Squirrel::Template;
use Constants qw($TMPLDIR %TEMPLATE_OPTS $URLBASE $CGI_URI $ADMIN_URI);

sub edit_link {
  my ($self, $id) = @_;
  return "/cgi-bin/admin/shopadmin.pl?id=$id&edit_product=1";
}

sub generate {
  my ($self, $article, $articles) = @_;

  my $product = Products->getByPkey($article->{id});
  my %acts;
  %acts =
    (
     $self->baseActs($articles, \%acts, $article, 0),
     product=> sub { CGI::escapeHTML($product->{$_[0]}) },
     admin =>
     sub {
       return '' unless $self->{admin};
       my $html = <<HTML;
<table>
<tr>
<td><form action="$CGI_URI/admin/shopadmin.pl">
<input type=hidden name="edit_product" value=1>
<input type=hidden name=id value=$product->{id}>
<input type=submit value="Edit Product"></form></td>
<td><form action="$ADMIN_URI">
<input type=submit value="Admin menu">
</form></td>
<td><form action="$CGI_URI/admin/admin.pl" target="_blank">
<input type=submit value="Display">
<input type=hidden name=admin value=0>
<input type=hidden name=id value="$product->{id}"></form></td>
</tr>
</table>
HTML
     },
    );
  return Squirrel::Template->new(%TEMPLATE_OPTS)
    ->show_page($TMPLDIR, $article->{template}, \%acts);
}

sub visible {
  my ($self, $article) = @_;
  return $article->{listed};
}

1;

__END__

=head1 NAME

  Generate::Product - generates product detail pages for BSE

=head1 DESCRIPTION

Like the NAME says.

=head1 TAGS

=over 4

=item product I<field>

Access to product fields of the product being rendered.  This is the
same as the C<article> I<field> tag for normal articles, but also give
you access to the product fields.

=item admin

Produces product specific administration links in admin mode.

=back

=head2 Product specific fields

=over 4

=item summary

An in-between length description of the article for use on the catalog
page.

=item leadTime

The number of days it takes to receive the product after it has been
ordered.

=item retailPrice

The cost to the customer of the product.  You need to use the C<money>
tag to format this field for display.

=item wholesalePrice

Your cost.  You need to use the C<money> tag to format this field for
display.

=item gst

The GST (in Australia) payable on the product.

=back

=cut
