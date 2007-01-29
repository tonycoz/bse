package BSE::UI::AdminShop;
use strict;
use base 'BSE::UI::AdminDispatch';
use Products;
use Product;
use BSE::TB::Orders;
use BSE::TB::OrderItems;
use BSE::Template;
#use Squirrel::ImageEditor;
use Constants qw(:shop $SHOPID $PRODUCTPARENT 
                 $SHOP_URI $CGI_URI $IMAGES_URI $AUTO_GENERATE);
use Images;
use Articles;
use BSE::Sort;
use BSE::Util::Tags qw(tag_hash);
use BSE::Util::Iterate;
use BSE::WebUtil 'refresh_to_admin';
use DevHelp::HTML qw(:default popup_menu);
use BSE::Arrows;
use BSE::CfgInfo 'product_options';

my %actions =
  (
   order_list => 'shop_order_list',
   order_list_filled => 'shop_order_list',
   order_list_unfilled => 'shop_order_list',
   order_list_unpaid => 'shop_order_list',
   order_list_incomplete => 'shop_order_list',
   order_detail => 'shop_order_detail',
   order_filled => 'shop_order_filled',
   product_detail => '',
   product_list => '',
  );

sub actions {
  \%actions;
}

sub rights {
  \%actions;
}

sub default_action {
  'product_list'
}

sub action_prefix {
  ''
}

#####################
# product management

sub embedded_catalog {
  my ($req, $catalog, $template) = @_;

  my $session = $req->session;
  use POSIX 'strftime';
  my $products = Products->new;
  my @list;
  if ($session->{showstepkids}) {
    my @allkids = $catalog->allkids;
    my %allgen = map { $_->{generator} => 1 } @allkids;
    for my $gen (keys %allgen) {
      (my $file = $gen . ".pm") =~ s!::!/!g;
      require $file;
    }
    @list = grep UNIVERSAL::isa($_->{generator}, 'Generate::Product'), $catalog->allkids;
    @list = map { $products->getByPkey($_->{id}) } @list;
  }
  else {
    @list = sort { $b->{displayOrder} <=> $a->{displayOrder} } 
      $products->getBy(parentid=>$catalog->{id});
  }
  my $list_index = -1;
  my $subcat_index = -1;
  my @subcats = sort { $b->{displayOrder} <=> $a->{displayOrder} } 
    grep $_->{generator} eq 'Generate::Catalog', 
    Articles->children($catalog->{id});

  my $blank = qq!<img src="$IMAGES_URI/trans_pixel.gif" width="17" height="13" border="0" align="absbottom" />!;

  my %acts;
  %acts =
    (
     BSE::Util::Tags->basic(\%acts, $req->cgi, $req->cfg),
     BSE::Util::Tags->admin(\%acts, $req->cfg),
     BSE::Util::Tags->secure($req),
     catalog => [ \&tag_hash, $catalog ],
     date => sub { display_date($list[$list_index]{$_[0]}) },
     money => sub { sprintf("%.2f", $list[$list_index]{$_[0]}/100.0) },
     iterate_products_reset => sub { $list_index = -1; },
     iterate_products =>
     sub {
       return ++$list_index < @list;
     },
     product => sub { escape_html($list[$list_index]{$_[0]}) },
     ifProducts => sub { @list },
     iterate_subcats_reset =>
     sub {
       $subcat_index = -1;
     },
     iterate_subcats => sub { ++$subcat_index < @subcats },
     subcat => sub { escape_html($subcats[$subcat_index]{$_[0]}) },
     ifSubcats => sub { @subcats },
     hiddenNote => 
     sub { $list[$list_index]{listed} == 0 ? "Hidden" : "&nbsp;" },
     move =>
     sub {
       my ($arg, $acts, $funcname, $templater) = @_;

       $req->user_can(edit_reorder_children => $catalog)
	 or return '';
       my ($img_prefix, $urladd) = DevHelp::Tags->get_parms($arg, $acts, $templater);
       defined $img_prefix or $img_prefix = '';
       defined $urladd or $urladd = '';
       @list > 1 or return '';
       # links to move products up/down
       my $refreshto = $ENV{SCRIPT_NAME}."$urladd#cat".$catalog->{id};
       my $down_url = '';
       if ($list_index < $#list) {
	 if ($session->{showstepkids}) {
	   $down_url = "$CGI_URI/admin/move.pl?stepparent=$catalog->{id}&d=swap&id=$list[$list_index]{id}&other=$list[$list_index+1]{id}";
	 }
	 else {
	   $down_url = "$CGI_URI/admin/move.pl?id=$list[$list_index]{id}&d=swap&other=$list[$list_index+1]{id}";
	 }
       }
       my $up_url = '';
       if ($list_index > 0) {
	 if ($session->{showstepkids}) {
	   $up_url = "$CGI_URI/admin/move.pl?stepparent=$catalog->{id}&d=swap&id=$list[$list_index]{id}&other=$list[$list_index-1]{id}";
	 }
	 else {
	   $up_url = "$CGI_URI/admin/move.pl?id=$list[$list_index]{id}&d=swap&other=$list[$list_index-1]{id}";
	 }
       }
       return make_arrows($req->cfg, $down_url, $up_url, $refreshto, $img_prefix);
     },
     script=>sub { $ENV{SCRIPT_NAME} },
     embed =>
     sub {
       my ($which, $template) = split ' ', $_[0];
       $which eq 'subcat' or return "Unknown object $which embedded";
       return embedded_catalog($req, $subcats[$subcat_index], $template);
     },
     movecat =>
     sub {
       my ($arg, $acts, $funcname, $templater) = @_;

       $req->user_can(edit_reorder_children => $catalog)
	 or return '';
       @subcats > 1 or return '';
       # links to move catalogs up/down
       my ($img_prefix, $urladd) = DevHelp::Tags->get_parms($arg, $acts, $templater);
       defined $img_prefix or $img_prefix = '';
       defined $urladd or $urladd = '';
       my $refreshto = $ENV{SCRIPT_NAME}.$urladd;
       my $down_url = "";
       if ($subcat_index < $#subcats) {
	 $down_url = "$CGI_URI/admin/move.pl?id=$subcats[$subcat_index]{id}&d=swap&other=$subcats[$subcat_index+1]{id}&all=1";
       }
       my $up_url = "";
       if ($subcat_index > 0) {
	 $up_url = "$CGI_URI/admin/move.pl?id=$subcats[$subcat_index]{id}&d=swap&other=$subcats[$subcat_index-1]{id}&all=1";
       }
       return make_arrows($req->cfg, $down_url, $up_url, $refreshto, $img_prefix);
     },
    );

  return BSE::Template->get_page('admin/'.$template, $req->cfg, \%acts);
}

sub req_product_list {
  my ($class, $req, $message) = @_;

  my $cgi = $req->cgi;
  my $session = $req->session;
  my $shopid = $req->cfg->entryErr('articles', 'shop');
  my $shop = Articles->getByPkey($shopid);
  my @catalogs = sort { $b->{displayOrder} <=> $a->{displayOrder} }
    grep $_->{generator} eq 'Generate::Catalog', Articles->children($shopid);
  my $catalog_index = -1;
  $message ||= $cgi->param('m') || $cgi->param('message') || '';
  if (defined $cgi->param('showstepkids')) {
    $session->{showstepkids} = $cgi->param('showstepkids');
  }
  exists $session->{showstepkids} or $session->{showstepkids} = 1;
  my $products = Products->new;
  my @products = sort { $b->{displayOrder} <=> $a->{displayOrder} }
    $products->getBy(parentid => $shopid);
  my $product_index;

  my $blank = qq!<img src="$IMAGES_URI/trans_pixel.gif" width="17" height="13" border="0" align="absbottom" />!;

  my $it = BSE::Util::Iterate->new;

  my %acts;
  %acts =
    (
     BSE::Util::Tags->basic(\%acts, $cgi, $req->cfg),
     BSE::Util::Tags->admin(\%acts, $req->cfg),
     BSE::Util::Tags->secure($req),
     catalog=> sub { escape_html($catalogs[$catalog_index]{$_[0]}) },
     iterate_catalogs => sub { ++$catalog_index < @catalogs  },
     shopid=>sub { $shopid },
     shop => [ \&tag_hash, $shop ],
     script=>sub { $ENV{SCRIPT_NAME} },
     message => sub { $message },
     embed =>
     sub {
       my ($which, $template) = split ' ', $_[0];
       $which eq 'catalog' or return "Unknown object $which embedded";
       return embedded_catalog($req, $catalogs[$catalog_index], $template);
     },
     movecat =>
     sub {
       my ($arg, $acts, $funcname, $templater) = @_;

       $req->user_can(edit_reorder_children => $shopid)
	 or return '';
       @catalogs > 1 or return '';
       # links to move catalogs up/down
       my ($img_prefix, $urladd) = DevHelp::Tags->get_parms($arg, $acts, $templater);
       defined $img_prefix or $img_prefix = '';
       defined $urladd or $urladd = '';
       my $refreshto = $ENV{SCRIPT_NAME} . $urladd;
       my $down_url = '';
       if ($catalog_index < $#catalogs) {
	 $down_url = "$CGI_URI/admin/move.pl?id=$catalogs[$catalog_index]{id}&d=swap&other=$catalogs[$catalog_index+1]{id}";
       }
       my $up_url = '';
       if ($catalog_index > 0) {
	 $up_url = "$CGI_URI/admin/move.pl?id=$catalogs[$catalog_index]{id}&d=swap&other=$catalogs[$catalog_index-1]{id}";
       }
       return make_arrows($req->cfg, $down_url, $up_url, $refreshto, $img_prefix);
     },
     ifShowStepKids => sub { $session->{showstepkids} },
     $it->make_iterator(undef, 'product', 'products', \@products, \$product_index),
     move =>
     sub {
       my ($arg, $acts, $funcname, $templater) = @_;

       $req->user_can(edit_reorder_children => $shop)
	 or return '';
       my ($img_prefix, $urladd) = DevHelp::Tags->get_parms($arg, $acts, $templater);
       defined $img_prefix or $img_prefix = '';
       defined $urladd or $urladd = '';
       @products > 1 or return '';
       # links to move products up/down
       my $refreshto = $ENV{SCRIPT_NAME}."$urladd#cat".$shop->{id};
       my $down_url = '';
       if ($product_index < $#products) {
	 if ($session->{showstepkids}) {
	   $down_url = "$CGI_URI/admin/move.pl?stepparent=$shop->{id}&d=swap&id=$products[$product_index]{id}&other=$products[$product_index+1]{id}";
	 }
	 else {
	   $down_url = "$CGI_URI/admin/move.pl?id=$products[$product_index]{id}&d=swap&other=$products[$product_index+1]{id}";
	 }
       }
       my $up_url = '';
       if ($product_index > 0) {
	 if ($session->{showstepkids}) {
	   $up_url = "$CGI_URI/admin/move.pl?stepparent=$shop->{id}&d=swap&id=$products[$product_index]{id}&other=$products[$product_index-1]{id}";
	 }
	 else {
	   $up_url = "$CGI_URI/admin/move.pl?id=$products[$product_index]{id}&d=swap&other=$products[$product_index-1]{id}";
	 }
       }
       return make_arrows($req->cfg, $down_url, $up_url, $refreshto, $img_prefix);
     },
    );

  return $req->dyn_response('admin/product_list', \%acts);
}

sub req_product_detail {
  my ($class, $req) = @_;

  my $cgi = $req->cgi;
  my $id = $cgi->param('id');
  if ($id and
      my $product = Products->getByPkey($id)) {
    return product_form($req, $product, '', '', 'admin/product_detail');
  }
  else {
    return $class->req_product_list($req);
  }
}

sub product_form {
  my ($req, $product, $action, $message, $template) = @_;
  
  my $cgi = $req->cgi;
  $message ||= $cgi->param('m') || $cgi->param('message') || '';
  $template ||= 'add_product';
  my @catalogs;
  my $shopid = $req->cfg->entryErr('articles', 'shop');
  my @work = [ $shopid, '' ];
  while (@work) {
    my ($parent, $title) = @{shift @work};

    push(@catalogs, { id=>$parent, display=>$title }) if $title;
    my @kids = sort { $b->{displayOrder} <=> $a->{displayOrder} } 
      grep $_->{generator} eq 'Generate::Catalog',
      Articles->children($parent);
    $title .= ' / ' if $title;
    unshift(@work, map [ $_->{id}, $title.$_->{title} ], @kids);
  }
  my @files;
  if ($product->{id}) {
    require 'ArticleFiles.pm';
    @files = ArticleFiles->getBy(articleId=>$product->{id});
  }
  my $file_index;

  my @templates;
  push(@templates, "shopitem.tmpl")
    if grep -e "$_/shopitem.tmpl", BSE::Template->template_dirs($req->cfg);
  for my $dir (BSE::Template->template_dirs($req->cfg)) {
    if (opendir PROD_TEMPL, "$dir/products") {
      push @templates, map "products/$_",
	grep -f "$dir/products/$_" && /\.tmpl$/i, readdir PROD_TEMPL;
      closedir PROD_TEMPL;
    }
  }
  my %seen_templates;
  @templates = sort { lc($a) cmp lc($b) } 
    grep !$seen_templates{$_}++, @templates;

  my $stepcat_index;
  use OtherParents;
  # ugh
  my $realproduct;
  $realproduct = UNIVERSAL::isa($product, 'Product') ? $product : Products->getByPkey($product->{id});
  my @stepcats;
  @stepcats = OtherParents->getBy(childId=>$product->{id}) 
    if $product->{id};
  my @stepcat_targets = $realproduct->step_parents if $realproduct;
  my %stepcat_targets = map { $_->{id}, $_ } @stepcat_targets;
  my @stepcat_possibles = grep !$stepcat_targets{$_->{id}}, @catalogs;
  my @images;
  @images = $product->images
    if $product->{id};
#    @images = $imageEditor->images()
#      if $product->{id};
  my $image_index;
  my $avail_options = product_options($req->cfg);

  my $blank = qq!<img src="$IMAGES_URI/trans_pixel.gif" width="17" height="13" border="0" align="absbottom" />!;

  my %acts;
  %acts =
    (
     BSE::Util::Tags->basic(\%acts, $cgi, $req->cfg),
     BSE::Util::Tags->admin(\%acts, $req->cfg),
     BSE::Util::Tags->secure($req),
     catalogs => 
     sub {
       return popup_menu(-name=>'parentid',
                         -values=>[ map $_->{id}, @catalogs ],
                         -labels=>{ map { @$_{qw/id display/} } @catalogs },
                         -default=>($product->{parentid} || $PRODUCTPARENT));
     },
     product => [ \&tag_hash, $product ],
     action => sub { $action },
     message => sub { $message },
     script=>sub { $ENV{SCRIPT_NAME} },
     ifImage => sub { $product->{imageName} },
     hiddenNote => sub { $product->{listed} ? "&nbsp;" : "Hidden" },
     alloptions => 
     sub { escape_html(join(',', sort keys %$avail_options)) },
     templates => 
     sub {
       return popup_menu(-name=>'template', -values=>\@templates,
			 -default=>$product->{id} ? $product->{template} :
			 $templates[0]);
     },
     ifStepcats => sub { @stepcats },
     iterate_stepcats_reset => sub { $stepcat_index = -1; },
     iterate_stepcats => sub { ++$stepcat_index < @stepcats },
     stepcat => sub { escape_html($stepcats[$stepcat_index]{$_[0]}) },
     stepcat_targ =>
     sub {
       escape_html($stepcat_targets[$stepcat_index]{$_[0]});
     },
     movestepcat =>
     sub {
       my ($arg, $acts, $funcname, $templater) = @_;
       return ''
	 unless $req->user_can(edit_reorder_stepparents => $product),
       @stepcats > 1 or return '';
       my ($img_prefix, $urladd) = DevHelp::Tags->get_parms($arg, $acts, $templater);
       $img_prefix = '' unless defined $img_prefix;
       $urladd = '' unless defined $urladd;
       my $refreshto = escape_uri($ENV{SCRIPT_NAME}
				   ."?id=$product->{id}&$template=1$urladd#step");
       my $down_url = "";
       if ($stepcat_index < $#stepcats) {
	 $down_url = "$CGI_URI/admin/move.pl?stepchild=$product->{id}&id=$stepcats[$stepcat_index]{parentId}&d=swap&other=$stepcats[$stepcat_index+1]{parentId}&all=1";
       }
       my $up_url = "";
       if ($stepcat_index > 0) {
	 $up_url = "$CGI_URI/admin/move.pl?stepchild=$product->{id}&id=$stepcats[$stepcat_index]{parentId}&d=swap&other=$stepcats[$stepcat_index-1]{parentId}&all=1";
       }
       return make_arrows($req->cfg, $down_url, $up_url, $refreshto, $img_prefix);
     },
     ifStepcatPossibles => sub { @stepcat_possibles },
     stepcat_possibles => sub {
       popup_menu(-name=>'stepcat',
		  -values=>[ map $_->{id}, @stepcat_possibles ],
		  -labels=>{ map { $_->{id}, $_->{display}} @catalogs });
     },
     BSE::Util::Tags->
     make_iterator(\@files, 'file', 'files', \$file_index),
     BSE::Util::Tags->
     make_iterator(\@images, 'image', 'images', \$image_index),
    );

  return $req->dyn_response($template, \%acts);
}

#####################
# order management

sub order_list_low {
  my ($req, $template, $title, @orders) = @_;

  my $cgi = $req->cgi;

  my $from = $cgi->param('from');
  my $to = $cgi->param('to');
  use BSE::Util::SQL qw/now_sqldate sql_to_date date_to_sql/;
  use BSE::Util::Valid qw/valid_date/;
  my $today = now_sqldate();
  for my $what ($from, $to) {
    if (defined $what) {
      if ($what eq 'today') {
	$what = $today;
      }
      elsif (valid_date($what)) {
	$what = date_to_sql($what);
      }
      else {
	undef $what;
      }
    }
  }
  my $message = $cgi->param('m');
  defined $message or $message = '';
  $message = escape_html($message);
  if (defined $from || defined $to) {
    $from ||= '1900-01-01';
    $to ||= '2999-12-31';
    $cgi->param('from', sql_to_date($from));
    $cgi->param('to', sql_to_date($to));
    $to = $to."Z";
    @orders = grep $from le $_->{orderDate} && $_->{orderDate} le $to,
    @orders;
  }
  my @orders_work;
  my $order_index = -1;
  my %acts;
  %acts =
    (
     BSE::Util::Tags->basic(\%acts, $cgi, $req->cfg),
     BSE::Util::Tags->admin(\%acts, $req->cfg),
     BSE::Util::Tags->secure($req),
     #order=> sub { escape_html($orders_work[$order_index]{$_[0]}) },
     DevHelp::Tags->make_iterator2
     ( [ \&iter_orders, \@orders ],
       'order', 'orders', \@orders_work, \$order_index, 'NoCache'),
     script => sub { $ENV{SCRIPT_NAME} },
     title => sub { $title },
     ifHaveParam => sub { defined $cgi->param($_[0]) },
     ifParam => sub { $cgi->param($_[0]) },
     cgi => 
     sub { 
       my $value = $cgi->param($_[0]);
       defined $value or $value = '';
       escape_html($value);
     },
     message => $message,
    );
  $req->dyn_response("admin/$template", \%acts);
}

sub iter_orders {
  my ($orders, $args) = @_;

  return bse_sort({ id => 'n', total => 'n', filled=>'n' }, $args, @$orders);
}

sub req_order_list {
  my ($class, $req) = @_;

  my $orders = BSE::TB::Orders->new;
  my @orders = sort { $b->{orderDate} cmp $a->{orderDate} } 
    grep $_->{complete}, $orders->all;
  my $template = $req->cgi->param('template');
  unless (defined $template && $template =~ /^\w+$/) {
    $template = 'order_list';
  }

  return order_list_low($req, $template, 'Order list', @orders);
}

sub req_order_list_filled {
  my ($class, $req) = @_;

  my $orders = BSE::TB::Orders->new;
  my @orders = sort { $b->{orderDate} cmp $a->{orderDate} } 
    grep $_->{complete} && $_->{filled} && $_->{paidFor}, $orders->all;

  return order_list_low($req, 'order_list_filled', 'Order list - Filled orders', @orders);
}

sub req_order_list_unfilled {
  my ($class, $req) = @_;

  my $orders = BSE::TB::Orders->new;
  my @orders = sort { $b->{orderDate} cmp $a->{orderDate} } 
    grep $_->{complete} && !$_->{filled} && $_->{paidFor}, $orders->all;

  return order_list_low($req, 'order_list_unfilled', 
			'Order list - Unfilled orders', @orders);

}

sub req_order_list_unpaid {
  my ($class, $req) = @_;

  my $orders = BSE::TB::Orders->new;
  my @orders = sort { $b->{orderDate} cmp $a->{orderDate} } 
    grep $_->{complete} && !$_->{paidFor}, $orders->all;

  return order_list_low($req, 'order_list_unpaid', 
			'Order list - Incomplete orders', @orders);
}

sub req_order_list_incomplete {
  my ($class, $req) = @_;

  my $orders = BSE::TB::Orders->new;
  my @orders = sort { $b->{orderDate} cmp $a->{orderDate} } 
    grep !$_->{complete}, $orders->all;

  return order_list_low($req, 'order_list_incomplete', 
			'Order list - Incomplete orders', @orders);
}

sub cart_item_opts {
  my ($req, $cart_item, $product) = @_;

  my $avail_options = product_options($req->cfg);

  my @options = ();
  my @values = split /,/, $cart_item->{options};
  my @ids = split /,/, $product->{options};
  for my $opt_index (0 .. $#ids) {
    my $entry = $avail_options->{$ids[$opt_index]};
    my $option = {
		  id=>$ids[$opt_index],
		  value=>$values[$opt_index],
		  desc => $entry->{desc} || $ids[$opt_index],
		 };
    if ($entry->{labels}) {
      $option->{label} = $entry->{labels}{$values[$opt_index]};
    }
    else {
      $option->{label} = $option->{value};
    }
    push(@options, $option);
  }

  return @options;
}

sub nice_options {
  my (@options) = @_;

  if (@options) {
    return '('.join(", ", map("$_->{desc} $_->{label}", @options)).')';
  }
  else {
    return '';
  }
}

sub tag_siteuser {
  my ($order, $rsiteuser, $arg) = @_;

  unless ($$rsiteuser) {
    $$rsiteuser = $order->siteuser || {};
  }

  my $siteuser = $$rsiteuser;
  return '' unless $siteuser->{id};

  my $value = $siteuser->{$arg};
  defined $value or $value = '';

  return escape_html($value);
}

sub req_order_detail {
  my ($class, $req, $message) = @_;

  my $cgi = $req->cgi;
  my $id = $cgi->param('id');
  if ($id and
      my $order = BSE::TB::Orders->getByPkey($id)) {
    $message ||= $cgi->param('m') || '';
    my @lines = $order->items;
    my @products = map { Products->getByPkey($_->{productId}) } @lines;
    my $line_index = -1;
    my $product;
    my @options;
    my $option_index = -1;
    my $siteuser;
    my %acts;
    %acts =
      (
       BSE::Util::Tags->basic(\%acts, $cgi, $req->cfg),
       BSE::Util::Tags->admin(\%acts, $req->cfg),
       BSE::Util::Tags->secure($req),
       item => sub { escape_html($lines[$line_index]{$_[0]}) },
       iterate_items_reset => sub { $line_index = -1 },
       iterate_items => 
       sub { 
	 if (++$line_index < @lines ) {
	   $option_index = -1;
	   @options = cart_item_opts($req,
				     $lines[$line_index],
				     $products[$line_index]);
	   return 1;
	 }
	 return 0;
       },
       order => [ \&tag_hash, $order ],
       #money => 
       #sub { 
#	 my ($func, $args) = split ' ', $_[0], 2;
#	 return sprintf("%.2f", $acts{$func}->($args)/100.0)
#       },
       date =>
       sub {
	 my ($func, $args) = split ' ', $_[0], 2;
	 return display_date($acts{$func}->($args));
       },
       extension =>
       sub {
	 sprintf("%.2f", $lines[$line_index]{units} * $lines[$line_index]{$_[0]}/100.0)
       },
       product => sub { escape_html($products[$line_index]{$_[0]}) },
       script => sub { $ENV{SCRIPT_NAME} },
       iterate_options_reset => sub { $option_index = -1 },
       iterate_options => sub { ++$option_index < @options },
       option => sub { CGI::escapeHTML($options[$option_index]{$_[0]}) },
       ifOptions => sub { @options },
       options => sub { nice_options(@options) },
       message => sub { $message },
       siteuser => [ \&tag_siteuser, $order, \$siteuser, ],
      );

    return $req->dyn_response('admin/order_detail', \%acts);
  }
  else {
    return $class->req_order_list($req);
  }
}

sub req_order_filled {
  my ($class, $req) = @_;

  my $id = $req->cgi->param('id');
  if ($id and
      my $order = BSE::TB::Orders->getByPkey($id)) {
    my $filled = $req->cgi->param('filled');
    $order->{filled} = $filled;
    if ($order->{filled}) {
      $order->{whenFilled} = epoch_to_sql_datetime(time);
      my $user = $req->user;
      if ($user) {
	$order->{whoFilled} = $user->{logon};
      }
      else {
	$order->{whoFilled} = defined($ENV{REMOTE_USER})
	  ? $ENV{REMOTE_USER} : "-unknown-";
      }
    }
    $order->save();
    if ($req->cgi->param('detail')) {
      return $class->req_order_detail($req);
    }
    else {
      return $class->req_order_list($req);
    }
  }
  else {
    return $class->req_order_list($req);
  }
}

#####################
# utilities
# perhaps some of these belong in a class...

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

# convert an epoch time to sql format
sub epoch_to_sql_datetime {
  use POSIX 'strftime';
  my ($time) = @_;

  return strftime('%Y-%m-%d %H:%M', localtime $time);
}

1;

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

Used to display the list of orders.  You can also specify a template
parameter to the order_list target, and perform filtering and sorting
within the template.

=over 4

=item order I<name>

The given field of the order.

=item iterator ... orders [filter-sort-spec]

Iterates over the orders in reverse orderDate order.

The [filter-sort-spec] can contain none, either or both of the following:

=over

=item filter= field op value, ...

filter the data by checking the given expression.

eg. filter= filled == 0

=item sort= [+|-] keyword, ...

Sorts the result by the specified fields, in reverse if preceded by '-'.

=back

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

=item iterator ... options

Iterates over the options set for the current order item.

=item option I<field>

Access to a field of the option, any of id, value, desc or label.

=item ifOptions

Conditional tag, true if the current product has any options.

=item options

A laid-out list of the options set for the current order item.

=back

=cut
