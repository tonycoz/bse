package Generate::Product;
use strict;
use Generate::Article;
use Products;
use BSE::TB::Images;
use base qw(Generate::Article);
use Constants qw(:shop $CGI_URI $ADMIN_URI);
use Carp qw(confess);
use BSE::Util::HTML;
use BSE::Util::Tags qw(tag_article);

our $VERSION = "1.001";

sub edit_link {
  my ($self, $id) = @_;
  return "/cgi-bin/admin/add.pl?id=$id";
}

sub generate {
  my ($self, $article, $articles) = @_;

  my $product = Products->getByPkey($article->{id});
  return $self->SUPER::generate($product, $articles);
}

sub _default_admin {
  my ($self, $product, $embedded) = @_;

       my $html = <<HTML;
<table>
<tr>
<td><form action="$CGI_URI/admin/add.pl">
<input type=hidden name="edit" value=1>
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
}

sub baseActs {
  my ($self, $articles, $acts, $product, $embedded) = @_;

  unless ($product->isa('Product')) {
    $product = Products->getByPkey($product->{id});
  }

  my @stepcats = $product->step_parents();
  my $stepcat_index;
  my @options = $product->option_descs($self->{cfg});
  my $option_index;

  return
    (
     $self->SUPER::baseActs($articles, $acts, $product, $embedded),
     product=> [ \&tag_article, $product, $self->{cfg} ],
     admin => [ tag_admin => $self, $product, 'product', $embedded ],
     iterate_options_reset => sub { $option_index = -1 },
     iterate_options => sub { ++$option_index < @options },
     option => 
     sub {
       if ($_[0] eq 'popup') {
	 my $option = $options[$option_index];
	 my @args =
	   (
	    -name      => $option->{id},
	    -id        => $option->{id},
	    -values    => $option->{values},
	    -override  => 1,
	   );
	 push(@args, -labels=>$option->{labels}) if $option->{labels};
	 push(@args, -default=>$option->{default}) if $option->{default};
	 return BSE::Util::HTML::popup_menu(@args);
       }
       else {
	 return escape_html($options[$option_index]{$_[0]})
       }
     },
     ifOptions => sub { @options },
     iterate_stepcats_reset => sub { $stepcat_index = -1 },
     iterate_stepcats => sub { ++$stepcat_index < @stepcats },
     stepcat => sub { tag_article($stepcats[$stepcat_index], $self->{cfg}, $_[0]) },
     ifStepCats => sub { @stepcats },
    );
}

sub visible {
  my ($self, $article) = @_;
  return $article->{listed};
}

sub get_real_article {
  my ($self, $article) = @_;

  return Products->getByPkey($article->{id});
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

=item iterator ... options

Iterates over the options available for the product, setting the option tag.

=item option popup

The popup list of values for the current option.

=item option field

Retrieves the given field from the option.  Most commonly you just
want the desc field.

  <:if Options:>
  <!-- you might want to start a table here -->
  <:iterator begin options:>
  <:option desc:>: <:option popup:>
  <:iterator end options:>
  <!-- and end a table here -->
  <:or Options:><:eif Options:>

=item iterator ... stepcats

Iterates over any step parents of the product, setting the I<stepcat>
for each element.

=item stepcat I<field>

Access to fields of the step catalogs of the parent.

=item ifStepCats

Conditional tag, true if the product has any step catalogs.

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

=item options

The raw version of the options that can be set for this product.

=back

=cut
