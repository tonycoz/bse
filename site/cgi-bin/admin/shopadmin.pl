#!/usr/bin/perl -w
use strict;
use lib '../modules';
use CGI ':standard';
use CGI::Carp 'fatalsToBrowser';
#use Carp; # 'verbose';
use Products;
use Product;
use Orders;
use Order;
use OrderItems;
use OrderItem;
use Constants qw($TMPLDIR);
use Squirrel::Template;
use Squirrel::ImageEditor;
use Constants qw($SHOPID $PRODUCTPARENT $SECURLBASE 
                 $SHOP_URI $CGI_URI $IMAGES_URI $AUTO_GENERATE);
use CGI::Cookie;
use Apache::Session::MySQL;
use Images;
use Articles;

my %cookies = fetch CGI::Cookie;
my $sessionid;
$sessionid = $cookies{sessionid}->value if exists $cookies{sessionid};
my %session;

my $dh = single DatabaseHandle;
eval {
  tie %session, 'Apache::Session::MySQL', $sessionid,
    {
     Handle=>$dh->{dbh},
     LockHandle=>$dh->{dbh}
    };
};
if ($@ && $@ =~ /Object does not exist/) {
  # try again
  undef $sessionid;
  tie %session, 'Apache::Session::MySQL', $sessionid,
    {
     Handle=>$dh->{dbh},
     LockHandle=>$dh->{dbh}
    };
}
unless ($sessionid) {
  # save the new sessionid
  print "Set-Cookie: ",CGI::Cookie->new(-name=>'sessionid', -value=>$session{_session_id}),"\n";
}

# this shouldn't be necessary, but it stopped working and this fixed it
# <sigh>
END {
  untie %session;
}

my %acts;
%acts = 
  (
   articleType=>sub { 'Product' },
  );

param();

my $imageEditor = Squirrel::ImageEditor->new(session=>\%session,
					     extras=>\%acts,
					     keep => [ 'id' ]);


my %what_to_do =
  (
   order_list=>\&order_list,
   order_detail=>\&order_detail,
   edit_product=>\&edit_product,
   add_product=>\&add_product,
   save_product=>\&save_product,
   delete_product=>\&delete_product,
   undelete_product=>\&undelete_product,
   product_detail=>\&product_detail,
   back=>\&img_return,
  );

my @modifiable = qw(body retailPrice wholesalePrice gst release expire parentid leadTime);
my %modifiable = map { $_=>1 } @modifiable;

if ($imageEditor->action($CGI::Q)) {
  exit;
}

while (my ($key, $func) = each %what_to_do) {
  if (param($key)) {
    $func->();
    exit;
  }
}

product_list();

#####################
# product management

sub product_list {
  my @catalogs = Articles->children($SHOPID);
  my $catalog_index = -1;
  my $products = Products->new;
  my @list = sort { $b->{displayOrder} cmp $a->{displayOrder} } $products->all;
  my $list_index = -1;
  my $message = param('message') || '';
  use POSIX 'strftime';
  my $today = strftime('%Y-%m-%d', localtime);
  my %acts =
    (
     catalog=> sub { CGI::escapeHTML($catalogs[$catalog_index]{$_[0]}) },
     iterate_catalogs =>
     sub {
       if (++$catalog_index < @catalogs) {
         $list_index = -1;
         @list = $products->getBy(parentid=>$catalogs[$catalog_index]{id});
         return 1;
       }
       return 0;
     },
     product => sub { CGI::escapeHTML($list[$list_index]{$_[0]}) },
     date => sub { display_date($list[$list_index]{$_[0]}) },
     money => sub { sprintf("%.2f", $list[$list_index]{$_[0]}/100.0) },
     iterate_products =>
     sub {
       return ++$list_index < @list;
     },
     script=>sub { $ENV{SCRIPT_NAME} },
     message => sub { $message },
     hiddenNote => 
     sub { $list[$list_index]{listed} == 0 ? "Hidden" : "&nbsp;" },
     shopid=>sub { $SHOPID },
     move =>
     sub {
       # links to move up/down
       my $html = '';
       my $refreshto = CGI::escape($ENV{SCRIPT_NAME});
       if ($list_index < $#list) {
	 $html .= <<HTML;
<a href="$CGI_URI/admin/move.pl?id=$list[$list_index]{id}&d=down&refreshto=$refreshto&all=1"><img src="$IMAGES_URI/admin/move_down.gif" width="17" height="13" border="0" alt="Move Down" align="absbottom"></a>
HTML
       }
       if ($list_index > 0) {
	 $html .= <<HTML;
<a href="$CGI_URI/admin/move.pl?id=$list[$list_index]{id}&d=up&refreshto=$refreshto&all=1"><img src="$IMAGES_URI/admin/move_up.gif" width="17" height="13" border="0" alt="Move Up" align="absbottom"></a>
HTML
       }
       return $html;
     },
    );

  page('product_list', \%acts);
}

sub add_product {
  my $product = { map { $_=>'' } Product->columns };

  $product->{leadTime} = 0;
  @$product{qw/retailPrice wholesalePrice gst/} = qw(0 0 0);
  $product->{release} = '2000-01-01';
  $product->{expire} = '9999-12-31';
  $product->{parentid} = param('parentid')
    if param('parentid');
  if (!exists $session{imageid} || $session{imageid} ne '') {
    $session{imageid} = '';
    $imageEditor->set([], 'tr');
  }

  product_form($product, "Add New");
}

sub edit_product {
  my $id = param('id');
  $id or shop_redirect('?product_list=1');
  my $product = Products->getByPkey($id)
    or shop_redirect("?message=Product+$id+not+found");
  if (!exists $session{imageid} || $session{imageid} != $id) {
    my @images = Images->getBy('articleId', $id);
    $session{imageid} = $id;
    $imageEditor->set(\@images, $product->{imagePos});
  }
  
  product_form($product, "Edit", '', 'edit_product');
}

sub save_product {
  my %product;

  for my $col (Product->columns) {
    $product{$col} = param($col) if defined param($col);
  }

  my $original;
  # we validate in here
  eval {
    if ($product{id}) {
      $original = Products->getByPkey($product{id})
	or shop_redirect("?message=Product+$product{id}+not+found");
    }
    if ($original) {
      # remove unmodifiable fields
      for my $key (keys %product) {
	$modifiable{$key} or delete $product{$key};
      }
    }
    else {
      $product{title} !~ /^\s*$/
	or die "No title entered";
      $product{summary} !~ /^\s*$/
	or die "No summary entered\n";
      $product{body} !~ /^\s*$/
	or die "No description entered\n";
      $product{leadTime} =~ /^\d+$/
	or die "No lead time entered\n";

    }
    use AdminUtil 'save_thumbnail';
    save_thumbnail($original, \%product);
    sql_date(\$product{release})
      or die "Invalid release date\n";
    sql_date(\$product{expire})
      or die "Invalid expiry date\n";
    money_to_cents(\$product{retailPrice})
      or die "Invalid price\n";
    money_to_cents(\$product{wholesalePrice})
      or $product{wholesalePrice} = undef;
    money_to_cents(\$product{gst})
      or die "Invalid gst\n";
  };
  if ($@) {
    # CGI::Carp messes with the die message <sigh>
    $@ =~ s/\[[^\]]*\][^:]+://; 
    if ($original) {
      for my $key (keys %$original) {
	$product{$key} = $original->{key};
      }
    }
    product_form(\%product, $original ? "Edit" : "Add New", $@);
    return;
  }

  # save the product
  $product{parentid} ||= $PRODUCTPARENT;
  $product{titleImage} = '';
  $product{keyword} ||= '';
  $product{template} = 'shopitem.tmpl';
  $product{threshold} = 0; # ignored
  $product{summaryLength} = 200; # ignored
  $product{level} = 2;
  $product{lastModified} = epoch_to_sql(time);
  $product{imagePos} = $imageEditor->imagePos || 'tr';
  $product{generator} = 'Generate::Product';
  
  if ($original) {
    @$original{keys %product} = values %product;
    $original->save();

    # out with the old
    my @oldimages = Images->getBy('articleId', $original->{id});
    for my $image (@oldimages) {
      $image->remove();
    }
    # in with the new
    my @images = $imageEditor->images();
    for my $image (@images) {
      Images->add($original->{id}, @$image{qw/image alt width height/});
    }
    $imageEditor->clear();
    delete $session{imageid};

    use Util 'generate_article';
    generate_article('Articles', $original) if $AUTO_GENERATE;

    shop_redirect('?message=Saved'); # redirect to product list
  }
  else {
    # set these properly afterwards
    $product{link} = '';
    $product{admin} = '';
    $product{listed} = 2;
    $product{displayOrder} = time;

    my @data = @product{Product->columns};
    shift @data;

    my $product = Products->add(@data);
    if (!$product) {
      for my $key (keys %$original) {
	$product{$key} = $original->{$key} unless defined $product{$key};
      }
      product_form(\%product, "Add New", DBI->errstr);
    }
    else {
      # update the link info
      $product->{link} = $SECURLBASE . $SHOP_URI . '/shop'.$product->{id}.'.html';
      $product->{admin} = "$CGI_URI/admin/admin.pl?id=$product->{id}";
      $product->save();

      # and save the images
      my @images = $imageEditor->images();
      for my $image (@images) {
	Images->add($product->{id}, @$image{qw/image alt width height/});
      }
      $imageEditor->clear();
      delete $session{imageid};

      use Util 'generate_article';
      generate_article('Articles', $product) if $AUTO_GENERATE;

      shop_redirect(''); # redirect to product list
    }
  }
}

sub delete_product {
  my $id = param('id');
  if ($id and
     my $product = Products->getByPkey($id)) {
    $product->{listed} = 0;
    $product->save();
    use Util 'generate_article';
    generate_article('Articles', $product) if $AUTO_GENERATE;
    shop_redirect("?message=Product+hidden");
  }
  else {
    product_list();
  }
}

sub undelete_product {
  my $id = param('id');
  if ($id and
     my $product = Products->getByPkey($id)) {
    $product->{listed} = 1;
    $product->save();
    use Util 'generate_article';
    generate_article('Articles', $product) if $AUTO_GENERATE;
    shop_redirect("?message=Product+shown");
  }
  else {
    product_list();
  }
}

sub product_detail {
  my $id = param('id');
  if ($id and
      my $product = Products->getByPkey($id)) {
    product_form($product, '', '', 'product_detail');
  }
  else {
    product_list();
  }
}
sub product_form {
  my ($product, $action, $message, $template) = @_;

  defined($message) or $message = '';
  $template ||= 'add_product';
  my @catalogs = sort { $b->{displayOrder} <=> $a->{displayOrder} } 
                          Articles->children($SHOPID);

  my %acts;
  %acts =
    (
     catalogs => 
     sub {
       return popup_menu(-name=>'parentid',
                         -values=>[ map $_->{id}, @catalogs ],
                         -labels=>{ map { @$_{qw/id title/} } @catalogs },
                         -default=>($product->{parentid} || $PRODUCTPARENT),
                         -override=>1);
     },
     product => sub { CGI::escapeHTML($product->{$_[0]}) },
     date => sub { display_date($product->{$_[0]}) },
     money => sub { sprintf("%.2f", $product->{$_[0]}/100.0) },
     action => sub { $action },
     message => sub { $message },
     script=>sub { $ENV{SCRIPT_NAME} },
     ifImage => sub { $product->{imageName} },
     hiddenNote => sub { $product->{listed} ? "&nbsp;" : "Hidden" },
    );

  page($template, \%acts);
}

sub img_return {
  if (exists $session{imageid}) {
    if ($session{imageid}) {
      param('id', $session{imageid});
      edit_product();
    }
    else {
      add_product();
    }
  }
  else {
    product_list(); # something wierd
  }
}

#####################
# order management

sub order_list {
  my $orders = Orders->new;
  my @orders = sort { $b->{orderDate} cmp $a->{orderDate} } $orders->all;

  my $order_index = -1;
  my %acts;
  %acts =
    (
     order=> sub { CGI::escapeHTML($orders[$order_index]{$_[0]}) },
     iterate_orders => sub { ++$order_index < @orders },
     money => sub { sprintf("%.2f", $orders[$order_index]{$_[0]}/100.0) },
     date => sub { display_date($orders[$order_index]{$_[0]}) },
     script => sub { $ENV{SCRIPT_NAME} },
    );
  page('order_list', \%acts);
}

sub order_detail {
  my $id = param('id');
  if ($id and
      my $order = Orders->getByPkey($id)) {
    my @lines = OrderItems->getBy('orderId', $id);
    my $line_index = -1;
    my $product;
    my %acts;
    %acts =
      (
       item => sub { CGI::escapeHTML($lines[$line_index]{$_[0]}) },
       iterate_items => 
       sub { 
	 if (++$line_index < @lines ) {
	   $product = Products->getByPkey($lines[$line_index]{productId});
	 }
	 else {
	   return 0;
	 }
       },
       order => sub { CGI::escapeHTML($order->{$_[0]}) },
       money => 
       sub { 
	 my ($func, $args) = split ' ', $_[0], 2;
	 return sprintf("%.2f", $acts{$func}->($args)/100.0)
       },
       date =>
       sub {
	 my ($func, $args) = split ' ', $_[0], 2;
	 return display_date($acts{$func}->($args));
       },
       extension =>
       sub {
	 sprintf("%.2f", $lines[$line_index]{units} * $lines[$line_index]{$_[0]}/100.0)
       },
       product => sub { CGI::escapeHTML($product->{$_[0]}) },
       script => sub { $ENV{SCRIPT_NAME} },
      );
    page('order_detail', \%acts);
  }
  else {
    order_list();
  }
}

#####################
# utilities
# perhaps some of these belong in a class...

sub page {
  my ($which, $acts, $iter) = @_;

  my $templ = Squirrel::Template->new;

  print "Content-Type: text/html\n\n";
  print $templ->show_page($TMPLDIR, 'admin/' . $which . ".tmpl", $acts, $iter);
}

sub shop_redirect {
  my $url = shift;
  print "Content-Type: text/html\n";
  print "Refresh: 0; url=\"$ENV{SCRIPT_NAME}$url\"\n\n<html></html>\n";
  exit;
}

# format an ANSI SQL date for display
sub display_date {
  my ($date) = @_;
  
  if ( my ($year, $month, $day) = 
       ($date =~ /^(\d+)-(\d+)-(\d+)/)) {
    return sprintf("%02d/%02d/%04d", $day, $month, $year);
  }
  return $date;
}

# convert a user entered date from dd/mm/yyyy to ANSI sql format
# we try to parse flexibly here
sub sql_date {
  my $str = shift;
  my ($year, $month, $day);

  # look for a date
  if (($day, $month, $year) = ($$str =~ m!(\d+)/(\d+)/(\d+)!)) {
    $year += 2000 if $year < 100;

    return $$str = sprintf("%04d-%02d-%02d", $year, $month, $day);
  }
  return undef;
}

sub money_to_cents {
  my $money = shift;

  $$money =~ /^\s*(\d+(\.\d*)|\.\d+)/
    or return undef;
  return $$money = sprintf("%.0f ", $$money * 100);
}

# convert an epoch time to sql format
sub epoch_to_sql {
  use POSIX 'strftime';
  my ($time) = @_;

  return strftime('%Y-%m-%d', localtime $time);
}


__END__

=head1 NAME

shopadmin.pl - administration for the online-store tables

=head1 SYNOPSYS

(This is a CGI script.)

=head1 DESCRIPTION

shopadmin.pl gives a UI to edit the product table, and view the orders and 
order_item tables.

=head1 TEMPLATES

shopadmin.pl uses a few templates from the templates/admin directory.

=head2 product_list.tmpl

=over 4

=item product I<name>

Access to product fields.

=item date I<name>

Formats the I<name> field of the product as a date.

=item money I<name>

Formats the I<name> integer field as a 2 decimal place money value.

=item iterator ... products

Iterates over the products database in reverse expire order.

=item script

The name of the current script for use in URLs.

=item message

An error message that may have been passed in the 'message' parameter.

=item hiddenNote

'Deleted' if the expire date of the current product has passed.

=back

=head2 add_product.tmpl
=head2 edit_product.tmpl
=head2 product_detail.tmpl

These use the same tags.

=over 4

=item product I<name>

The specified field of the product.

=item date I<name>

Formats the given field of the product as a date.

=item money I<name>

Formats the given integer field of the product as money.

=item action

Either 'Add New' or 'Edit'.

=item message

The message parameter passed into the script.

=item script

The name of the script, for use in urls.

=item ifImage

Conditional, true if the product has an image.

=item hiddenNote

"Hidden" if the product is hidden.

=back

=head2 order_list.tmpl

Used to display the list of orders.

=over 4

=item order I<name>

The given field of the order.

=item iterator ... orders

Iterates over the orders in reverse orderDate order.

=item money I<name>

The given field of the current order formatted as money.

=item date I<name>

The given field of the current order formatted as a date.

=item script

The name of the script, for use in urls.

=back

=head2 order_detail.tmpl

Used to display the details for an order.

=over 4

=item item I<name>

Displays the given field of a line item

=item iterator ... items

Iterates over the line items in the order.

=item order I<name>

The given field of the order.

=item money I<func> I<args>

Formats the given functions return value as money.

=item date I<func> I<args>

Formats the  given function return value as a date.

=item extension I<name>

Takes the given field for the current item multiplied by the units column.

=item product I<name>

The given product field of the product for the current item.

=item script

The name of the current script (for use in urls).

=back

=cut
