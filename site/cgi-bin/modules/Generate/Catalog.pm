package Generate::Catalog;

our $VERSION = "1.004";

use strict;
use Generate;
use Products;
use base 'BSE::Generate::Article';
use BSE::Template;
use Constants qw($CGI_URI $ADMIN_URI);
use BSE::Regen qw(generate_button);
use OtherParents;
use DevHelp::HTML;
use BSE::Arrows;
use BSE::Util::Iterate;
use BSE::CfgInfo qw(cfg_dist_image_uri);

sub _default_admin {
  my ($self, $article, $embedded) = @_;

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

sub tag_moveallcat {
  my ($self, $allcats, $rindex, $article, $arg, $acts, $funcname, $templater) = @_;

  return '' unless $self->{admin};
  return '' unless $self->{request};
  return '' 
    unless $self->{request}->user_can(edit_reorder_children => $article);
  return '' unless @$allcats > 1;

  my ($img_prefix, $urladd) = 
    DevHelp::Tags->get_parms($arg, $acts, $templater);
  $img_prefix = '' unless defined $img_prefix;
  $urladd = '' unless defined $urladd;
  
  my $can_move_up = $$rindex > 0;
  my $can_move_down = $$rindex < $#$allcats;
  return '' unless $can_move_up || $can_move_down;
  my $myid = $allcats->[$$rindex]{id};
  my $top = $self->{top} || $article;
  my $refreshto = "$CGI_URI/admin/admin.pl?id=$top->{id}$urladd";
  my $down_url = "";
  if ($can_move_down) {
    my $nextid = $allcats->[$$rindex+1]{id};
    $down_url = "$CGI_URI/admin/move.pl?stepparent=$article->{id}&d=swap&id=$myid&other=$nextid";
  }
  my $up_url = "";
  if ($can_move_up) {
    my $previd = $allcats->[$$rindex-1]{id};
    $up_url = "$CGI_URI/admin/move.pl?stepparent=$article->{id}&d=swap&id=$myid&other=$previd";
  }
  return make_arrows($self->{cfg}, $down_url, $up_url, $refreshto, $img_prefix);
}

sub tag_ifAnyProductOptions {
  my ($self, $lookup, $arg) = @_;

  $arg ||= "product";

  my $entry = $lookup->{$arg}
    or die "** No such product $arg **";
  my ($rindex, $rdata) = @$entry;
  $$rindex >= 0 && $$rindex < @$rdata
    or die "** not in an iterator for $arg **";
  my @options = $rdata->[$$rindex]->option_descs($self->{cfg});

  return scalar(@options);
}

sub baseActs {
  my ($self, $articles, $acts, $article, $embedded) = @_;

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
  my @allkids = $article->all_visible_kids;
  # make sure we have all of the inheritance info
  my %generate = map { $_->{generator} => 1 } @allkids;
  for my $gen (keys %generate) {
    (my $file = $gen . ".pm") =~ s!::!/!g;
    require $file;
  }
  my @allprods = grep UNIVERSAL::isa($_->{generator}, 'BSE::Generate::Product'), 
    @allkids;
  for (@allprods) {
    unless ($_->isa('Product')) {
      $_ = Products->getByPkey($_->{id});
    }
  }
  my @allcats = grep UNIVERSAL::isa($_->{generator}, 'Generate::Catalog'), 
    @allkids;

  # for article ifUnderThreshold handler
  $self->{kids}{$article->{id}}{allprods} = \@allprods;
  $self->{kids}{$article->{id}}{allcats} = \@allcats;

  my $allprod_index;
  my $catalog_index = -1;
  my $allcat_index;
  my %named_product_iterators =
    (
     product => [ \$product_index, \@products ],
     allprod => [ \$allprod_index, \@allprods ],
    );
  my $it = BSE::Util::Iterate->new;
  my $cfg = $self->{cfg};
  my $art_it = BSE::Util::Iterate::Article->new(cfg => $cfg);
  my $image_uri = cfg_dist_image_uri();
  my %work =
    (
     $self->SUPER::baseActs($articles, $acts, $article, $embedded),
     #article => sub { escape_html($article->{$_[0]}) },
     $art_it->make_iterator(undef, 'product', 'products', \@products, 
			\$product_index),
     admin => [ tag_admin => $self, $article, 'catalog', $embedded ],
     # for rearranging order in admin mode
     moveDown=>
     sub {
       if ($self->{admin} && $product_index < $#products) {
	 my $html = <<HTML;
 <a href="$CGI_URI/admin/move.pl?id=$products[$product_index]{id}&amp;d=down"><img src="$image_uri/admin/move_down.gif" width="17" height="13" border="0" alt="Move Down" align="absbottom" /></a>
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
 <a href="$CGI_URI/admin/move.pl?id=$products[$product_index]{id}&amp;d=up"><img src="$image_uri/admin/move_up.gif" width="17" height="13" border="0" alt="Move Up" align="absbottom" /></a>
HTML
	 chop $html;
	 return $html;
       }
       else {
	 return '';
       }
     },
     $art_it->make_iterator(undef, 'allprod', 'allprods', \@allprods, 
			\$allprod_index),
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

       my $can_move_up = $allprod_index > 0;
       my $can_move_down = $allprod_index < $#allprods;
       return '' unless $can_move_up || $can_move_down;
       my $blank = qq(<img src="$image_uri/trans_pixel.gif" width="17" height="13" border="0" align="absbotton" alt="" />);
       my $myid = $allprods[$allprod_index]{id};
       my $top = $self->{top} || $article;
       my $refreshto = "$CGI_URI/admin/admin.pl?id=$top->{id}$urladd";
       my $down_url = "";
       if ($can_move_down) {
	 my $nextid = $allprods[$allprod_index+1]{id};
	 $down_url = "$CGI_URI/admin/move.pl?stepparent=$article->{id}&d=swap&id=$myid&other=$nextid";
       }
       my $up_url = "";
       if ($can_move_up) {
	 my $previd = $allprods[$allprod_index-1]{id};
	 $up_url = "$CGI_URI/admin/move.pl?stepparent=$article->{id}&d=swap&id=$myid&other=$previd";
       }
       
       return make_arrows($self->{cfg}, $down_url, $up_url, $refreshto, $img_prefix);
     },
     ifAnyProds => scalar(@allprods),
     $art_it->make_iterator(undef, 'stepprod', 'stepprods', \@stepprods,
			\$stepprod_index),
     ifStepProds => sub { @stepprods },
     $art_it->make_iterator(undef, 'catalog', 'catalogs', \@subcats, 
			\$catalog_index),
     ifSubcats => sub { @subcats },
     $art_it->make_iterator(undef, 'allcat', 'allcats', \@allcats, \$allcat_index),
     moveallcat => 
     [ \&tag_moveallcat, $self, \@allcats, \$allcat_index, $article ],
     ifAnyProductOptions =>
     [ tag_ifAnyProductOptions => $self, \%named_product_iterators ],
    );
  my $oldurl = $work{url};
  my $urlbase = $self->{cfg}->entryVar('site', 'url');
  $work{url} =
    sub {
      my $value = $oldurl->(@_);
      return $value if $value =~ /^<:/; # handle "can't do it"
      unless ($value =~ /^\w+:/) {
        # put in the base site url
        $value = $urlbase . $value;
      }
      return $value;
    };

  return %work;
}

1;

__END__

=head1 NAME

  Generate::Catalog - page generator class for catalog pages

=head1 DESCRIPTION

  This class is used to generate catalog pages for BSE.  It derives
  from L<BSE::Generate::Article>, and inherits it's tags.

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
BSE::Generate::Article, so there is some obsolete code still present.

=cut
