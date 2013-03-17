package BSE::UI::AdminShop;
use strict;
use base 'BSE::UI::AdminDispatch';
use Products;
use Product;
use BSE::TB::Orders;
use BSE::TB::OrderItems;
use BSE::Template;
use Constants qw(:shop $SHOPID $PRODUCTPARENT 
                 $SHOP_URI $CGI_URI $AUTO_GENERATE);
use BSE::TB::Images;
use Articles;
use BSE::Sort;
use BSE::Util::Tags qw(tag_hash tag_error_img tag_object_plain tag_object tag_article);
use BSE::Util::Iterate;
use BSE::WebUtil 'refresh_to_admin';
use BSE::Util::HTML qw(:default popup_menu);
use BSE::Arrows;
use BSE::Shop::Util qw(:payment order_item_opts nice_options payment_types);
use BSE::CfgInfo qw(cfg_dist_image_uri);

our $VERSION = "1.018";

my %actions =
  (
   order_list => 'shop_order_list',
   order_list_filled => 'shop_order_list',
   order_list_unfilled => 'shop_order_list',
   order_list_unpaid => 'shop_order_list',
   order_list_incomplete => 'shop_order_list',
   order_detail => 'shop_order_detail',
   order_filled => 'shop_order_filled',
   order_paid => 'shop_order_paid',
   order_unpaid => 'shop_order_unpaid',
   order_save => 'shop_order_save',
   product_detail => '',
   product_list => '',
   paypal_refund => 'bse_shop_order_refund_paypal',
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

  my $image_uri = cfg_dist_image_uri();
  my $blank = qq!<img src="$image_uri/trans_pixel.gif" width="17" height="13" border="0" align="absbottom" />!;

  my %acts;
  %acts =
    (
     $req->admin_tags,
     catalog => [ \&tag_hash, $catalog ],
     iterate_products_reset => sub { $list_index = -1; },
     iterate_products =>
     sub {
       return ++$list_index < @list;
     },
     product => 
     sub { 
       $list_index >= 0 && $list_index < @list
	 or return '** outside products iterator **';
       my $product = $list[$list_index];
       return tag_article($product, $req->cfg, $_[0]);
     },
     ifProducts => sub { @list },
     iterate_subcats_reset =>
     sub {
       $subcat_index = -1;
     },
     iterate_subcats => sub { ++$subcat_index < @subcats },
     subcat => sub { tag_article($subcats[$subcat_index], $req->cfg, $_[0]) },
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

  my $image_uri = cfg_dist_image_uri();
  my $blank = qq!<img src="$image_uri/trans_pixel.gif" width="17" height="13" border="0" align="absbottom" />!;

  my $it = BSE::Util::Iterate->new;

  my %acts;
  %acts =
    (
     $req->admin_tags,
     catalog=> sub { tag_article($catalogs[$catalog_index], $req->cfg, $_[0]) },
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
  $template ||= 'admin/product_detail';
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
    require BSE::TB::ArticleFiles;
    @files = BSE::TB::ArticleFiles->getBy(articleId=>$product->{id});
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

  my $image_uri = cfg_dist_image_uri();
  my $blank = qq!<img src="$image_uri/trans_pixel.gif" width="17" height="13" border="0" align="absbottom" />!;

  my %acts;
  %acts =
    (
     $req->admin_tags,
     catalogs => 
     sub {
       return popup_menu(-name=>'parentid',
                         -values=>[ map $_->{id}, @catalogs ],
                         -labels=>{ map { @$_{qw/id display/} } @catalogs },
                         -default=>($product->{parentid} || $PRODUCTPARENT));
     },
     product => [ \&tag_article, $product, $req->cfg ],
     action => sub { $action },
     message => sub { $message },
     script=>sub { $ENV{SCRIPT_NAME} },
     ifImage => sub { $product->{imageName} },
     hiddenNote => sub { $product->{listed} ? "&nbsp;" : "Hidden" },
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

=item tag all_order_count
X<tags, shop admin, all_order_count>C<all_order_count>

Returns a count of orders matching a set of conditions.

=cut

sub tag_all_order_count {
  my ($args, $acts, $funcname, $templater) = @_;

  my $query;
  if ($args =~ /\S/) {
    if (eval "\$query = [ $args ]; 1 ") {
      return BSE::TB::Orders->getCount($query);
    }
    else {
      return "<!-- error handling args: $@ -->";
    }
  }
  else {
    return BSE::TB::Orders->getCount();
  }
}

#####################
# order management

sub order_list_low {
  my ($req, $template, $title, $conds, $options) = @_;

  my $cgi = $req->cgi;

  $options ||= {};
  my $order = delete $options->{order};
  defined $order or $order = 'id desc';
  my $datelimit = delete $options->{datelimit};
  defined $datelimit or $datelimit = 1;

  my $from = $cgi->param('from');
  my $to = $cgi->param('to');
  use BSE::Util::SQL qw/now_sqldate sql_to_date date_to_sql sql_date/;
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
  if ($datelimit) {
    $from ||= sql_date(time() - 30 * 86_400);
  }
  if (defined $from || defined $to) {
    $from ||= '1900-01-01';
    $to ||= '2999-12-31';
    $cgi->param('from', sql_to_date($from));
    $cgi->param('to', sql_to_date($to));
    push @$conds,
      [ between => 'orderDate', $from, $to." 23:59:59" ];
  }

  my @simple_search_fields = qw/userId billEmail billFirstName billLastName billOrganization/;
  for my $key (@simple_search_fields) {
    my $value = $cgi->param($key);
    if (defined $value && $value =~ /\S/) {
      push @$conds, [ like => $key => '%' . $value . '%' ];
    }
  }

  my @stage = grep /\S/, map split (",", $_), $cgi->param("stage");
  if (@stage) {
    push @$conds,
      [ or =>
	map [ stage => $_ ], @stage
      ];
  }

  my $name = $cgi->param("name");
  if (defined $name && $name =~ /\S/) {
    push @$conds,
      [ or =>
	map [ like => $_ => '%' . $name . '%' ],
	qw(billFirstName billLastName billEmail userId)
      ];
  }

  my @ids = BSE::TB::Orders->getColumnBy
    (
     "id",
     $conds,
     { order => $order }
    );

  my $search_param;
  {
    my @param;
    for my $key (qw(from to stage name), @simple_search_fields) {
      for my $value (grep /\S/, $cgi->param($key)) {
	push @param, "$key=" . escape_uri($value);
      }
    }
    $search_param = join('&amp;', map escape_html($_), @param);
  }

  my $message = $cgi->param('m');
  defined $message or $message = '';
  $message = escape_html($message);

  my $it = BSE::Util::Iterate::Objects->new;
  my %acts;
  %acts =
    (
     $req->admin_tags,
     $it->make_paged
     (
      data => \@ids,
      fetch => [ getByPkey => 'BSE::TB::Orders' ],
      cgi => $req->cgi,
      single => "order",
      plural => "orders",
      session => $req->session,
      name => "orderlist",
      perpage_parm => "pp=50",
     ),
     title => sub { $title },
     ifHaveParam => sub { defined $cgi->param($_[0]) },
     ifParam => sub { $cgi->param($_[0]) },
     message => $message,
     ifError => 0,
     all_order_count => \&tag_all_order_count,
     search_param => $search_param,
     query => sub {
       require JSON;
       my $json = JSON->new;
       return $json->encode($conds);
     },
     stage_select => [ \&tag_stage_select_search, $req ],
    );
  $req->dyn_response("admin/$template", \%acts);
}

=item tag stage_select (search)

stage_select for order list filtering.

=cut

sub tag_stage_select_search {
  my ($req) = @_;

  my @stages = BSE::TB::Orders->settable_stages;
  unshift @stages, "";
  
  my %stage_labels = BSE::TB::Orders->stage_labels;
  $stage_labels{""} = "(No stage filter)";
  my $stage = $req->cgi->param("stage") || "";
  return popup_menu
    (
     -name => "stage",
     -values => \@stages,
     -default => $stage,
     -labels => \%stage_labels,
    );
}

sub iter_orders {
  my ($orders, $args) = @_;

  return bse_sort({ id => 'n', total => 'n', filled=>'n' }, $args, @$orders);
}

=item target order_list
X<shopadmin targets, order_list>X<order_list target>

List all completed orders.

By default limits to the last 30 days.

=cut

sub req_order_list {
  my ($class, $req) = @_;

  my $template = $req->cgi->param('template');
  unless (defined $template && $template =~ /^\w+$/) {
    $template = 'order_list';
  }

  my @conds = 
    (
     [ '<>', complete => 0 ],
    );

  return order_list_low($req, $template, 'Order list', \@conds);
}

=item target order_list_filled
X<shopadmin targets, order_list_filled>X<order_list_filled target>

List all filled orders.

By default limits to the last 30 days.

=cut

sub req_order_list_filled {
  my ($class, $req) = @_;

  my @conds =
    (
     [ '<>', complete => 0 ],
     [ '<>', filled => 0 ],
     #[ '<>', paidFor => 0 ],
    );

  return order_list_low($req, 'order_list_filled', 'Order list - Filled orders',
		       \@conds);
}

=item target order_list_unfilled
X<shopadmin targets, order_list_unfilled>X<order_list_unfilled target>

List completed but unfilled orders.

Unlike the other order lists, this lists oldest order first, and does
not limit to the last 30 days.

=cut

sub req_order_list_unfilled {
  my ($class, $req) = @_;

  my @conds =
    (
     [ '<>', complete => 0 ],
     [ filled => 0 ],
    );

  return order_list_low($req, 'order_list_unfilled', 
			'Order list - Unfilled orders',
			\@conds, { order => 'id asc', datelimit => 0 });
}

sub req_order_list_unpaid {
  my ($class, $req) = @_;

  my @conds =
    (
     [ '<>', complete => 0 ],
     [ paidFor => 0 ],
    );

  return order_list_low($req, 'order_list_unpaid', 
			'Order list - Unpaid orders', \@conds);
}

=item target order_list_incomplete
X<shopadmin targets, order_list_incomplete>X<order_list_incomplete>

List incomplete orders, ie. orders that the user abandoned before the
payment step was complete.

By default limits to the last 30 days.

=cut

sub req_order_list_incomplete {
  my ($class, $req) = @_;

  my @conds =
    (
     [ complete => 0 ]
    );

  return order_list_low($req, 'order_list_incomplete', 
			'Order list - Incomplete orders', \@conds);
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

sub tag_shipping_method_select {
  my ($self, $order) = @_;

  my @methods = all_shippers();

  return popup_menu
    (
     -name => "shipping_name",
     -values => [ map $_->{id}, @methods ],
     -labels => { map { $_->{id} => $_->{name} } @methods },
     -id => "shipping_name",
     -default => $order->shipping_name,
    );
}

sub tag_stage_select {
  my ($self, $req, $order) = @_;

  my @stages = BSE::TB::Orders->settable_stages;
  
  my %stage_labels = BSE::TB::Orders->stage_labels;
  return popup_menu
    (
     -name => "stage",
     -values => \@stages,
     -default => $order->stage,
     -labels => \%stage_labels,
    );
}

=item target order_detail

Display the details of an order.

Variables set:

=over

=item *

order - the order being displayed

=item *

payment_types - a list of configured payment types

=item *

payment_type_desc - a description of the current payment type

=back

=cut

sub req_order_detail {
  my ($class, $req, $errors) = @_;

  my $cgi = $req->cgi;
  my $id = $cgi->param('id');
  if ($id and
      my $order = BSE::TB::Orders->getByPkey($id)) {
    my $message = $req->message($errors);
    my @lines = $order->items;
    my @products = map { Products->getByPkey($_->{productId}) } @lines;
    my $line_index = -1;
    my $product;
    my @options;
    my $option_index = -1;
    my $siteuser;
    my $it = BSE::Util::Iterate->new;

    $req->set_variable(order => $order);
    my @pay_types = payment_types();
    $req->set_variable(payment_types => \@pay_types);
    my ($pay_type) = grep $_->{id} == $order->paymentType, @pay_types;
    $req->set_variable(payment_type_desc => $pay_type ? $pay_type->{desc} : "Unknown");
    my %acts;
    %acts =
      (
       $req->admin_tags,
       item => sub { escape_html($lines[$line_index]{$_[0]}) },
       iterate_items_reset => sub { $line_index = -1 },
       iterate_items => 
       sub { 
	 if (++$line_index < @lines ) {
	   $option_index = -1;
	   @options = order_item_opts($req,
				      $lines[$line_index],
				      $products[$line_index]);
	   return 1;
	 }
	 return 0;
       },
       order => [ \&tag_object, $order ],
       extension =>
       sub {
	 sprintf("%.2f", $lines[$line_index]{units} * $lines[$line_index]{$_[0]}/100.0)
       },
       product => sub { tag_article($products[$line_index], $req->cfg, $_[0]) },
       script => sub { $ENV{SCRIPT_NAME} },
       iterate_options_reset => sub { $option_index = -1 },
       iterate_options => sub { ++$option_index < @options },
       option => sub { escape_html($options[$option_index]{$_[0]}) },
       ifOptions => sub { @options },
       options => sub { nice_options(@options) },
       message => $message,
       error_img => [ \&tag_error_img, $errors ],
       siteuser => [ \&tag_siteuser, $order, \$siteuser, ],
       $it->make
       (
	single => "shipping_method",
	plural => "shipping_methods",
	code => \&all_shippers,
       ),
       shipping_method_select =>
       [ tag_shipping_method_select => $class, $order ],
       stage_select =>
       [ tag_stage_select => $class, $req, $order ],
       stage_description => escape_html($order->stage_description($req->language)),
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

=item target order_paid

Mark the order identified by C<id> as paid.

Optionally accepts C<paymentType> which replaces the current payment
type.

Requires csrfp token C<shop_order_paid>.

=cut

sub req_order_paid {
  my ($self, $req) = @_;

  $req->check_csrf("shop_order_paid")
    or return $self->req_order_list($req, "Bad or missing csrf token: " . $req->csrf_error);

  return $self->_set_order_paid($req, 1);
}

=item target order_unpaid

Mark the order identified by C<id> as unpaid.

Requires csrfp token C<shop_order_unpaid>.

=cut

sub req_order_unpaid {
  my ($self, $req) = @_;

  $req->check_csrf("shop_order_unpaid")
    or return $self->req_order_list($req, "Bad or missing csrf token: " . $req->csrf_error);

  return $self->_set_order_paid($req, 0);
}

sub _set_order_paid {
  my ($class, $req, $value) = @_;

  my $id = $req->cgi->param('id');
  if ($id and
      my $order = BSE::TB::Orders->getByPkey($id)) {
    if ($order->paidFor != $value) {
      if ($value) {
	my $pay_type = $req->cgi->param("paymentType");
	if (defined $pay_type && $pay_type =~ /^[0-9]+$/) {
	  $order->set_paymentType($pay_type);
	}
      }
      else {
	$order->is_manually_paid
	  or return $class->req_order_detail($req, "You can only unpay manually paid orders");
      }

      $order->set_paidFor($value);

      # we want to reset paid_manually if we reset paidFor, so if the
      # customer pays via the public interface the order doesn't get
      # treated as manually paid
      $order->set_paid_manually($value);

      if ($value) {
	$req->audit
	  (
	   component => "shopadmin:order:paid",
	   level => "notice",
	   object => $order,
	   msg => "Order " . $order->id . " marked paid",
	  );
      }
      else {
	$req->audit
	  (
	   component => "shopadmin:order:unpaid",
	   level => "notice",
	   object => $order,
	   msg => "Order " . $order->id . " marked unpaid",
	  );
      }
      $order->save();
    }

    return $req->get_refresh
      ($req->url("shopadmin", { a_order_detail => 1, id => $id }));
  }
  else {
    return $class->req_order_list($req);
  }
}

sub req_paypal_refund {
  my ($self, $req) = @_;

  my $id = $req->cgi->param('id');
  if ($id and
      my $order = BSE::TB::Orders->getByPkey($id)) {
    require BSE::PayPal;
    my $msg;
    unless (BSE::PayPal->refund_order(order => $order,
				      req => $req,
				      msg => \$msg)) {
      return $self->req_order_detail($req, $msg);
    }

    return $req->get_refresh($req->url(shopadmin => { "a_order_detail" => 1, id => $id }));
  }
  else {
    $req->flash_error("Missing or invalid order id");
    return $self->req_order_list($req);
  }
}

=item order_save

Make changes to an order, only a limited set of fields can be changed.

Parameters, all optional:

=over

=item *

id - id of the order.  Required.

=item *

shipping_method - if automated shipping calculations are disabled, the
id of the dummy shipping method to set for the order.

=item *

freight_tracking - the freight tracking code for the shipment.

=item *

stage - order stage, one of unprocessed, backorder, picked, shipped,
cancelled.

=back

Requires csrfp token C<shop_order_save>.

=cut

sub req_order_save {
  my ($self, $req) = @_;

  $req->check_csrf("shop_order_save")
    or return $self->req_product_list($req, "Bad or missing csrf token: " . $req->csrf_error);

  my $cgi = $req->cgi;
  my $id = $cgi->param("id");
  $id && $id =~ /^[0-9]+$/
    or return $self->req_product_list($req, "No order id supplied");

  my $order = BSE::TB::Orders->getByPkey($id)
    or return $self->req_product_list($req, "No such order id");

  my %errors;
  my $save = 0;

  my $new_freight_tracking = 0;
  my $code = $cgi->param("freight_tracking");
  if (defined $code && $code ne $order->freight_tracking) {
    $order->set_freight_tracking($code);
    ++$new_freight_tracking;
    ++$save;
  }

  my $new_shipping_name = 0;
  my $shipping_name = $cgi->param("shipping_name");
  if (defined $shipping_name
      && $shipping_name ne $order->shipping_name) {
    my @ship = all_shippers();
    my ($entry) = grep $_->{id} eq $shipping_name, @ship;
    if ($entry) {
      $order->set_shipping_name($entry->{id});
      $order->set_shipping_method($entry->{name});
      ++$new_shipping_name;
      ++$save;
    }
    else {
      $errors{shipping_method} = "msg:bse/admin/shop/saveorder/badmethod:$shipping_name";
    }
  }

  my $new_stage = 0;
  my ($stage) = $cgi->param("stage");
  my ($stage_note) = $cgi->param("stage_note");
  if (defined $stage && $stage ne $order->stage
     || defined $stage_note && $stage_note =~ /\S/) {
    my @stages = BSE::TB::Orders->settable_stages;
    if (grep $_ eq $stage, @stages) {
      ++$new_stage;
      ++$save;
    }
    else {
      $errors{stage} = "msg:bse/admin/shop/saveorder/badstage:$stage";
    }
  }

  keys %errors
    and return $self->req_order_detail($req, \%errors);

  if ($save) {
    if ($new_freight_tracking) {
      $req->audit
	(
	 component => "shopadmin:orders:saveorder",
	 object => $order,
	 msg => "New freight tracking code set: '" . $order->freight_tracking . "'",
	 level => "notice",
	);
    }
    if ($new_shipping_name) {
      $req->audit
	(
	 component => "shopadmin:orders:saveorder",
	 object => $order,
	 msg => "New shippping method set: '" . $order->shipping_name . "/" . $order->shipping_method . "'",
	 level => "notice",
	);
    }
    if ($new_stage) {
      $order->new_stage(scalar $req->user, $stage, $stage_note);
    }

    $order->save;
    $req->flash("msg:bse/admin/shop/saveorder/saved");
  }
  else {
    $req->flash("msg:bse/admin/shop/saveorder/nochanges");
  }

  my $url = $cgi->param("r") || $req->url("shopadmin", { a_order_detail => 1, id => $order->id });

  return $req->get_refresh($url);
}

#####################
# utilities
# perhaps some of these belong in a class...

# format an ANSI SQL date for display
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


sub all_shippers {
  require BSE::Shipping;

  my $cfg = BSE::Cfg->single;
  my @shippers = BSE::TB::Orders->dummy_shipping_methods;
  if ($cfg->entry("shop", "shipping", 0)) {
    my @normal = BSE::Shipping->get_couriers($cfg);
    push @shippers, map 
      +{
	id => $_->name,
	name => $_->description
       }, @normal;
  }

  return @shippers;
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

