#!/usr/bin/perl -w
# -d:ptkdb
BEGIN { $ENV{DISPLAY} = '192.168.32.15:0.0'; }

use strict;
use FindBin;
use lib "$FindBin::Bin/../modules";

#use Carp; # 'verbose';
use Products;
use Product;
use Orders;
use Order;
use OrderItems;
use OrderItem;
use BSE::Template;
#use Squirrel::ImageEditor;
use Constants qw(:shop $SHOPID $PRODUCTPARENT 
                 $SHOP_URI $CGI_URI $IMAGES_URI $AUTO_GENERATE);
use Images;
use Articles;
use BSE::Sort;
use BSE::Util::Tags;
use BSE::Request;
use Util 'refresh_to';

my $req = BSE::Request->new;
my $cfg = $req->cfg;
my $securlbase = $cfg->entryVar('site', 'secureurl');
my $baseurl =  $cfg->entryVar('site', 'url');
unless ($req->check_admin_logon()) {
  refresh_to("$baseurl/cgi-bin/admin/logon.pl");
  exit;
}
#my %session;
#BSE::Session->tie_it(\%session, $cfg);

#param();

my %what_to_do =
  (
   order_list=>\&order_list,
   order_list_filled=>\&order_list_filled,
   order_list_unfilled=>\&order_list_unfilled,
   order_list_unpaid => \&order_list_unpaid,
   order_detail=>\&order_detail,
   order_filled=>\&order_filled,
#     edit_product=>\&edit_product,
#     add_product=>\&add_product,
#     save_product=>\&save_product,
#   delete_product=>\&delete_product,
#   undelete_product=>\&undelete_product,
   product_detail=>\&product_detail,
#     add_stepcat=>\&add_stepcat,
#     del_stepcat=>\&del_stepcat,
#     save_stepcats => \&save_stepcats,
#     back=>\&img_return,
  );

my @modifiable = qw(body retailPrice wholesalePrice gst release expire 
                    parentid leadTime options template threshold
                    summaryLength);
my %modifiable = map { $_=>1 } @modifiable;

#  my $product;
#  my $id = param('id');
#  if ($id) {
#    $product = Products->getByPkey($id);
#  }
#  else {
#    my $parentid = param('parentid');
#    if ($parentid) {
#      $product = { parentid=>$parentid };
#    }
#  }
#  my %acts;
#  %acts = 
#    (
#     BSE::Util::Tags->basic(\%acts, $req->cgi, $cfg),
#     BSE::Util::Tags->admin(\%acts, $cfg),
#     articleType=>sub { 'Product' },
#     article=>
#     sub {
#       my $value = $product->{$_[0]};
#       defined $value or $value = '';
#       CGI::escapeHTML($value);
#     },
#     level => sub { 3; }, # doesn't really matter here
#    );

#  my $imageEditor = Squirrel::ImageEditor->new(session=>\%session,
#  					     extras=>\%acts,
#  					     keep => [ qw/id parentid/ ],
#  					     cfg=>$cfg);

#  if ($imageEditor->action($CGI::Q)) {
#    exit;
#  }

#  use BSE::FileEditor;
#  my $file_editor = 
#    BSE::FileEditor->new(session=>\%session, cgi=>$CGI::Q, cfg=>$cfg,
#  		       backopts=>{ edit_product=> 1});
#  if ($file_editor->process_files()) {
#    exit;
#  }

{
  my $cgi = $req->cgi;
  while (my ($key, $func) = each %what_to_do) {
    if ($cgi->param($key)) {
      $func->($req);
      exit;
    }
  }
}

product_list($req);

#####################
# product management

sub embedded_catalog {
  my ($req, $catalog, $template) = @_;

  my $session = $req->session;
  use POSIX 'strftime';
  my $products = Products->new;
  my @list;
  if ($session->{showstepkids}) {
    @list = grep $_->{generator} eq 'Generate::Product', $catalog->allkids;
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
     BSE::Util::Tags->basic(\%acts, $CGI::Q, $cfg),
     BSE::Util::Tags->admin(\%acts, $cfg),
     BSE::Util::Tags->secure($req),
     catalog => sub { CGI::escapeHTML($catalog->{$_[0]}) },
     date => sub { display_date($list[$list_index]{$_[0]}) },
     money => sub { sprintf("%.2f", $list[$list_index]{$_[0]}/100.0) },
     iterate_products_reset => sub { $list_index = -1; },
     iterate_products =>
     sub {
       return ++$list_index < @list;
     },
     product => sub { CGI::escapeHTML($list[$list_index]{$_[0]}) },
     ifProducts => sub { @list },
     iterate_subcats_reset =>
     sub {
       $subcat_index = -1;
     },
     iterate_subcats => sub { ++$subcat_index < @subcats },
     subcat => sub { CGI::escapeHTML($subcats[$subcat_index]{$_[0]}) },
     ifSubcats => sub { @subcats },
     hiddenNote => 
     sub { $list[$list_index]{listed} == 0 ? "Hidden" : "&nbsp;" },
     move =>
     sub {
       $req->user_can(edit_reorder_children => $catalog)
	 or return '';
       @list > 1 or return '';
       # links to move products up/down
       my $html = '';
       my $refreshto = CGI::escape($ENV{SCRIPT_NAME}."#cat".$catalog->{id});
       if ($list_index < $#list) {
	 if ($session->{showstepkids}) {
	   $html .= <<HTML;
<a href="$CGI_URI/admin/move.pl?stepparent=$catalog->{id}&d=swap&id=$list[$list_index]{id}&other=$list[$list_index+1]{id}&refreshto=$refreshto"><img src="$IMAGES_URI/admin/move_down.gif" width="17" height="13" border="0" alt="Move Down" align="absbottom"></a>
HTML
	 }
	 else {
	   $html .= <<HTML;
<a href="$CGI_URI/admin/move.pl?id=$list[$list_index]{id}&d=swap&other=$list[$list_index+1]{id}&refreshto=$refreshto&all=1"><img src="$IMAGES_URI/admin/move_down.gif" width="17" height="13" border="0" alt="Move Down" align="absbottom"></a>
HTML
	 }
       }
       else {
	 $html .= $blank;
       }
       if ($list_index > 0) {
	 if ($session->{showstepkids}) {
	   $html .= <<HTML;
<a href="$CGI_URI/admin/move.pl?stepparent=$catalog->{id}&d=swap&id=$list[$list_index]{id}&other=$list[$list_index-1]{id}&refreshto=$refreshto"><img src="$IMAGES_URI/admin/move_up.gif" width="17" height="13" border="0" alt="Move Up" align="absbottom"></a>
HTML
	 }
	 else {
	   $html .= <<HTML;
<a href="$CGI_URI/admin/move.pl?id=$list[$list_index]{id}&d=swap&other=$list[$list_index-1]{id}&refreshto=$refreshto&all=1"><img src="$IMAGES_URI/admin/move_up.gif" width="17" height="13" border="0" alt="Move Up" align="absbottom"></a>
HTML
	 }
       }
       else {
	 $html .= $blank;
       }
       $html =~ tr/\n//d;
       return $html;
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
       $req->user_can(edit_reorder_children => $catalog)
	 or return '';
       @subcats > 1 or return '';
       # links to move catalogs up/down
       my $html = '';
       my $refreshto = CGI::escape($ENV{SCRIPT_NAME});
       if ($subcat_index < $#subcats) {
	 $html .= <<HTML;
<a href="$CGI_URI/admin/move.pl?id=$subcats[$subcat_index]{id}&d=swap&other=$subcats[$subcat_index+1]{id}&refreshto=$refreshto&all=1"><img src="$IMAGES_URI/admin/move_down.gif" width="17" height="13" border="0" alt="Move Down" align="absbottom"></a>
HTML
       }
       else {
	 $html .= $blank;
       }
       if ($subcat_index > 0) {
	 $html .= <<HTML;
<a href="$CGI_URI/admin/move.pl?id=$subcats[$subcat_index]{id}&d=swap&other=$subcats[$subcat_index-1]{id}&refreshto=$refreshto&all=1"><img src="$IMAGES_URI/admin/move_up.gif" width="17" height="13" border="0" alt="Move Up" align="absbottom"></a>
HTML
       }
       else {
	 $html .= $blank;
       }
       $html =~ tr/\n//d;
       return $html;
     },
    );

  return BSE::Template->get_page('admin/'.$template, $cfg, \%acts);
}

sub product_list {
  my ($req, $message) = @_;

  my $cgi = $req->cgi;
  my $session = $req->session;
  my $shopid = $req->cfg->entryErr('articles', 'shop');
  my @catalogs = sort { $b->{displayOrder} <=> $a->{displayOrder} }
    Articles->children($shopid);
  my $catalog_index = -1;
  $message ||= $cgi->param('message') || '';
  if (defined $cgi->param('showstepkids')) {
    $session->{showstepkids} = $cgi->param('showstepkids');
  }
  exists $session->{showstepkids} or $session->{showstepkids} = 1;

  my $blank = qq!<img src="$IMAGES_URI/trans_pixel.gif" width="17" height="13" border="0" align="absbottom" />!;

  my %acts;
  %acts =
    (
     BSE::Util::Tags->basic(\%acts, $cgi, $cfg),
     BSE::Util::Tags->admin(\%acts, $cfg),
     BSE::Util::Tags->secure($req),
     catalog=> sub { CGI::escapeHTML($catalogs[$catalog_index]{$_[0]}) },
     iterate_catalogs => sub { ++$catalog_index < @catalogs  },
     shopid=>sub { $shopid },
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
       $req->user_can(edit_reorder_children => $shopid)
	 or return '';
       @catalogs > 1 or return '';
       # links to move catalogs up/down
       my $html = '';
       my $refreshto = CGI::escape($ENV{SCRIPT_NAME});
       if ($catalog_index < $#catalogs) {
	 $html .= <<HTML;
<a href="$CGI_URI/admin/move.pl?id=$catalogs[$catalog_index]{id}&d=swap&other=$catalogs[$catalog_index+1]{id}&refreshto=$refreshto&all=1"><img src="$IMAGES_URI/admin/move_down.gif" width="17" height="13" border="0" alt="Move Down" align="absbottom"></a>
HTML
       }
       else {
	 $html .= $blank;
       }
       if ($catalog_index > 0) {
	 $html .= <<HTML;
<a href="$CGI_URI/admin/move.pl?id=$catalogs[$catalog_index]{id}&d=swap&other=$catalogs[$catalog_index-1]{id}&refreshto=$refreshto&all=1"><img src="$IMAGES_URI/admin/move_up.gif" width="17" height="13" border="0" alt="Move Up" align="absbottom"></a>
HTML
       }
       else {
	 $html .= $blank;
       }
       $html =~ tr/\n//d;
       return $html;
     },
     ifShowStepKids => sub { $session->{showstepkids} },
    );

  page('product_list', \%acts);
}

#  sub add_product {

#    my $product = { map { $_=>'' } Product->columns };

#    $product->{leadTime} = 0;
#    @$product{qw/retailPrice wholesalePrice gst/} = qw(0 0 0);
#    use BSE::Util::SQL qw(now_sqldate);
#    $product->{release} = now_sqldate;
#    $product->{expire} = '9999-12-31';
#    $product->{parentid} = param('parentid')
#      if param('parentid');
#    if ($product->{parentid}) {
#      my $parent = Articles->getByPkey($product->{parentid});
#      if ($parent) {
#        $product->{threshold} = $parent->{threshold};
#        $product->{summaryLength} = $parent->{summaryLength};
#      }
#    }
#  #    if (!exists $session{imageid} || $session{imageid} ne '') {
#  #      $session{imageid} = '';
#  #      #$imageEditor->set([], 'tr');
#  #    }

#    product_form($product, "Add New");
#  }

#  sub edit_product {
#    my $id = param('id');
#    $id or shop_redirect('?product_list=1');
#    my $product = Products->getByPkey($id)
#      or shop_redirect("?message=Product+$id+not+found");
#  #    if (!exists $session{imageid} || $session{imageid} != $id) {
#  #      my @images = Images->getBy('articleId', $id);
#  #      $session{imageid} = $id;
#  #      $imageEditor->set(\@images, $product->{imagePos});
#  #    }
  
#    product_form($product, "Edit", '', 'edit_product');
#  }

#  sub save_product {
#    my %product;

#    for my $col (Product->columns) {
#      $product{$col} = param($col) if defined param($col);
#    }

#    my $original;
#    # we validate in here
#    eval {
#      if ($product{id}) {
#        $original = Products->getByPkey($product{id})
#  	or shop_redirect("?message=Product+$product{id}+not+found");
#      }
#      money_to_cents(\$product{retailPrice})
#        or die "Invalid price\n";
#      money_to_cents(\$product{wholesalePrice})
#        or $product{wholesalePrice} = undef;
#      money_to_cents(\$product{gst})
#        or die "Invalid gst\n";
    
#      if ($original) {
#        # remove unmodifiable fields
#        for my $key (keys %product) {
#  	$modifiable{$key} or delete $product{$key};
#        }
#      }
#      else {
#        $product{title} !~ /^\s*$/
#  	or die "No title entered\n";
#        $product{summary} !~ /^\s*$/
#  	or die "No summary entered\n";
#        $product{body} !~ /^\s*$/
#  	or die "No description entered\n";
#        $product{leadTime} =~ /^\d+$/
#  	or die "No lead time entered\n";

#      }
#      use AdminUtil 'save_thumbnail';
#      save_thumbnail($original, \%product);
#      sql_date(\$product{release})
#        or die "Invalid release date\n";
#      sql_date(\$product{expire})
#        or die "Invalid expiry date\n";
#      # options should only contain valid options
#      my @bad_opts = grep !$SHOP_PRODUCT_OPTS{$_}, 
#      split /,/, $product{options};
#      @bad_opts
#        and die "Bad product options '",join(',',@bad_opts),"' entered\n";
#    };
#    if ($@) {
#      # CGI::Carp messes with the die message <sigh>
#      $@ =~ s/\[[^\]]*\][^:]+://; 
#      if ($original) {
#        for my $key (keys %$original) {
#  	$product{$key} = $original->{$key};
#        }
#      }
#      product_form(\%product, $original ? "Edit" : "Add New", $@);
#      return;
#    }

#    # save the product
#    $product{parentid} ||= $PRODUCTPARENT;

#    my $parent = Articles->getByPkey($product{parentid})
#      or return product_form(\%product, $original ? "Edit" : "Add New",
#  			   "Unknown parent id");

#    $product{titleImage} = '';
#    $product{keyword} ||= '';
#    $product{template} ||= 'shopitem.tmpl';
#    $product{level} = $parent->{level} + 1;
#    $product{lastModified} = epoch_to_sql(time);
#    $product{imagePos} = 'tr';
#    $product{generator} = 'Generate::Product';
  
#    if ($original) {
#      @$original{keys %product} = values %product;
#      $original->save();

#      # out with the old
#  #      my @oldimages = Images->getBy('articleId', $original->{id});
#  #      for my $image (@oldimages) {
#  #        $image->remove();
#  #      }
#  #      # in with the new
#  #      my @images = $imageEditor->images();
#  #      my @cols = Image->columns;
#  #      splice @cols, 0, 2;
#  #      for my $image (@images) {
#  #        Images->add($original->{id}, @$image{@cols});
#  #      }
#  #      $imageEditor->clear();
#  #      delete $session{imageid};

#      use Util 'regen_and_refresh';
    
#      regen_and_refresh('Articles', $original, $AUTO_GENERATE,
#  		      shop_url("?message=Saved")); 

#      exit;
#    }
#    else {
#      # set these properly afterwards
#      $product{link} = '';
#      $product{admin} = '';
#      $product{listed} = 2;
#      $product{displayOrder} = time;

#      for my $col (qw(threshold summaryLength)) {
#        $product{$col} = $parent->{$col} unless exists $product{$col};
#      }

#      my @data = @product{Product->columns};
#      shift @data;

#      my $product = Products->add(@data);
#      if (!$product) {
#        for my $key (keys %$original) {
#  	$product{$key} = $original->{$key} unless defined $product{$key};
#        }
#        product_form(\%product, "Add New", DBI->errstr);
#      }
#      else {
#        # update the link info
#        $product->{link} = $securlbase . $SHOP_URI . '/shop'.$product->{id}.'.html';
#        $product->{admin} = "$CGI_URI/admin/admin.pl?id=$product->{id}";
#        $product->save();

#        # and save the images
#  #        my @images = $imageEditor->images();
#  #        for my $image (@images) {
#  #  	Images->add($product->{id}, @$image{qw/image alt width height/});
#  #        }
#  #        $imageEditor->clear();
#  #        delete $session{imageid};

#        use Util 'regen_and_refresh';
      
#        regen_and_refresh('Articles', $original, $AUTO_GENERATE,
#  			shop_url("?message=New+Product+Saved"));
#        exit;
#      }
#    }
#  }

#  sub delete_product {
#    my $id = param('id');
#    if ($id and
#       my $product = Products->getByPkey($id)) {
#      $product->{listed} = 0;
#      $product->save();
#      use Util 'generate_article';
#      generate_article('Articles', $product) if $AUTO_GENERATE;
#      shop_redirect("?message=Product+hidden");
#    }
#    else {
#      product_list();
#    }
#  }

#  sub undelete_product {
#    my $id = param('id');
#    if ($id and
#       my $product = Products->getByPkey($id)) {
#      $product->{listed} = 1;
#      $product->save();
#      use Util 'generate_article';
#      generate_article('Articles', $product) if $AUTO_GENERATE;
#      shop_redirect("?message=Product+shown");
#    }
#    else {
#      product_list();
#    }
#  }

sub product_detail {
  my ($req) = @_;

  my $cgi = $req->cgi;
  my $id = $cgi->param('id');
  if ($id and
      my $product = Products->getByPkey($id)) {
    product_form($req, $product, '', '', 'product_detail');
  }
  else {
    product_list($req);
  }
}
sub product_form {
  my ($req, $product, $action, $message, $template) = @_;
  
  my $cgi = $req->cgi;
  $message ||= $req->cgi->param('message') || '';
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
    if grep -e "$_/shopitem.tmpl", BSE::Template->template_dirs($cfg);
  for my $dir (BSE::Template->template_dirs($cfg)) {
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

  my $blank = qq!<img src="$IMAGES_URI/trans_pixel.gif" width="17" height="13" border="0" align="absbottom" />!;

  my %acts;
  %acts =
    (
     BSE::Util::Tags->basic(\%acts, $cgi, $cfg),
     BSE::Util::Tags->admin(\%acts, $cfg),
     BSE::Util::Tags->secure($req),
     catalogs => 
     sub {
       return popup_menu(-name=>'parentid',
                         -values=>[ map $_->{id}, @catalogs ],
                         -labels=>{ map { @$_{qw/id display/} } @catalogs },
                         -default=>($product->{parentid} || $PRODUCTPARENT),
                         -override=>1);
     },
     product => sub { CGI::escapeHTML($product->{$_[0]}) },
     action => sub { $action },
     message => sub { $message },
     script=>sub { $ENV{SCRIPT_NAME} },
     ifImage => sub { $product->{imageName} },
     hiddenNote => sub { $product->{listed} ? "&nbsp;" : "Hidden" },
     alloptions => 
     sub { CGI::escapeHTML(join(',', sort keys %SHOP_PRODUCT_OPTS)) },
     templates => 
     sub {
       return CGI::popup_menu(-name=>'template', -values=>\@templates,
                              -default=>$product->{id} ? $product->{template} :
                              $templates[0]);
     },
     ifStepcats => sub { @stepcats },
     iterate_stepcats_reset => sub { $stepcat_index = -1; },
     iterate_stepcats => sub { ++$stepcat_index < @stepcats },
     stepcat => sub { CGI::escapeHTML($stepcats[$stepcat_index]{$_[0]}) },
     stepcat_targ =>
     sub {
       CGI::escapeHTML($stepcat_targets[$stepcat_index]{$_[0]});
     },
     movestepcat =>
     sub {
       return ''
	 unless $req->user_can(edit_reorder_stepparents => $product),
       my $html = '';
       my $refreshto = CGI::escape($ENV{SCRIPT_NAME}
				   ."?id=$product->{id}&$template=1#step");
       @stepcats > 1 or return '';
       if ($stepcat_index < $#stepcats) {
	 $html .= <<HTML;
<a href="$CGI_URI/admin/move.pl?stepchild=$product->{id}&id=$stepcats[$stepcat_index]{parentId}&d=swap&other=$stepcats[$stepcat_index+1]{parentId}&refreshto=$refreshto&all=1"><img src="$IMAGES_URI/admin/move_down.gif" width="17" height="13" border="0" alt="Move Down" align="absbottom"></a>
HTML
       }
       else {
         $html .= $blank;
       }
       if ($stepcat_index > 0) {
	 $html .= <<HTML;
<a href="$CGI_URI/admin/move.pl?stepchild=$product->{id}&id=$stepcats[$stepcat_index]{parentId}&d=swap&other=$stepcats[$stepcat_index-1]{parentId}&refreshto=$refreshto&all=1"><img src="$IMAGES_URI/admin/move_up.gif" width="17" height="13" border="0" alt="Move Up" align="absbottom"></a>
HTML
       }
       else {
         $html .= $blank;
       }
       $html =~ tr/\n//d;
       return $html;
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

  page($template, \%acts);
}

#  sub img_return {
#    if (exists $session{imageid}) {
#      if ($session{imageid}) {
#        param('id', $session{imageid});
#        edit_product();
#      }
#      else {
#        add_product();
#      }
#    }
#    else {
#      product_list(); # something wierd
#    }
#  }

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
     BSE::Util::Tags->basic(\%acts, $CGI::Q, $cfg),
     BSE::Util::Tags->admin(\%acts, $cfg),
     BSE::Util::Tags->secure($req),
     #order=> sub { CGI::escapeHTML($orders_work[$order_index]{$_[0]}) },
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
       CGI::escapeHTML($value);
     },
    );
  page($template, \%acts);
}

sub iter_orders {
  my ($orders, $args) = @_;

  return bse_sort({ id => 'n', total => 'n', filled=>'n' }, $args, @$orders);
}

sub order_list {
  my ($req) = @_;

  $req->user_can('shop_order_list')
    or return product_list($req, "You don't have access to the order list");
    
  my $orders = Orders->new;
  my @orders = sort { $b->{orderDate} cmp $a->{orderDate} } $orders->all;
  my $template = $req->cgi->param('template');
  unless (defined $template && $template =~ /^\w+$/) {
    $template = 'order_list';
  }

  order_list_low($req, $template, 'Order list', @orders);
}

sub order_list_filled {
  my ($req) = @_;

  $req->user_can('shop_order_list')
    or return product_list($req, "You don't have access to the order list");

  my $orders = Orders->new;
  my @orders = sort { $b->{orderDate} cmp $a->{orderDate} } 
    grep $_->{filled} && $_->{paidFor}, $orders->all;

  order_list_low($req, 'order_list_filled', 'Order list - Filled orders', @orders);
}

sub order_list_unfilled {
  my ($req) = @_;

  $req->user_can('shop_order_list')
    or return product_list($req, "You don't have access to the order list");

  my $orders = Orders->new;
  my @orders = sort { $b->{orderDate} cmp $a->{orderDate} } 
    grep !$_->{filled} && $_->{paidFor}, $orders->all;

  order_list_low($req, 'order_list_unfilled', 'Order list - Unfilled orders', 
		 @orders);
}

sub order_list_unpaid {
  my ($req) = @_;

  $req->user_can('shop_order_list')
    or return product_list($req, "You don't have access to the order list");

  my $orders = Orders->new;
  my @orders = sort { $b->{orderDate} cmp $a->{orderDate} } 
    grep !$_->{paidFor}, $orders->all;

  order_list_low($req, 'order_list_unpaid', 'Order list - Incomplete orders', 
		 @orders);
}

sub cart_item_opts {
  my ($cart_item, $product) = @_;

  my @options = ();
  my @values = split /,/, $cart_item->{options};
  my @ids = split /,/, $product->{options};
  for my $opt_index (0 .. $#ids) {
    my $entry = $SHOP_PRODUCT_OPTS{$ids[$opt_index]};
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

sub order_detail {
  my ($req) = @_;

  $req->user_can('shop_order_detail')
    or return product_list($req, "You don't have access to order details");

  my $cgi = $req->cgi;
  my $id = $cgi->param('id');
  if ($id and
      my $order = Orders->getByPkey($id)) {
    my @lines = OrderItems->getBy('orderId', $id);
    my @products = map { Products->getByPkey($_->{productId}) } @lines;
    my $line_index = -1;
    my $product;
    my @options;
    my $option_index = -1;
    my %acts;
    %acts =
      (
       BSE::Util::Tags->basic(\%acts, $CGI::Q, $cfg),
       BSE::Util::Tags->admin(\%acts, $cfg),
       BSE::Util::Tags->secure($req),
       item => sub { CGI::escapeHTML($lines[$line_index]{$_[0]}) },
       iterate_items_reset => sub { $line_index = -1 },
       iterate_items => 
       sub { 
	 if (++$line_index < @lines ) {
	   $option_index = -1;
	   @options = cart_item_opts($lines[$line_index],
				     $products[$line_index]);
	   return 1;
	 }
	 return 0;
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
       product => sub { CGI::escapeHTML($products[$line_index]{$_[0]}) },
       script => sub { $ENV{SCRIPT_NAME} },
       iterate_options_reset => sub { $option_index = -1 },
       iterate_options => sub { ++$option_index < @options },
       option => sub { CGI::escapeHTML($options[$option_index]{$_[0]}) },
       ifOptions => sub { @options },
       options => sub { nice_options(@options) },
      );
    page('order_detail', \%acts);
  }
  else {
    order_list();
  }
}

sub order_filled {
  my ($req) = @_;

  $req->user_can('shop_order_filled')
    or return product_list($req, "You don't have access to order details");

  my $id = $req->cgi->param('id');
  if ($id and
      my $order = Orders->getByPkey($id)) {
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
      order_detail($req);
    }
    else {
      order_list($req);
    }
  }
  else {
    order_list($req);
  }
}

#####################
# Step parents

#  sub add_stepcat {
#    require 'BSE/Admin/StepParents.pm';
#    my $productid = param('id');
#    defined($productid)
#      or return product_list("No id supplied to add_stepcat");
#    int($productid) eq $productid+0
#      or return product_list("Invalid product id supplied to add_stepcat");
#    my $product = Products->getByPkey($productid)
#      or return product_list("Cannot find product id $productid");
  
#    eval {
#      my $catid = param('stepcat');
#      defined($catid)
#        or die "No stepcat supplied to add_stepcat";
#      int($catid) eq $catid
#        or die "Invalid stepcat supplied to add_stepcat";
#      my $catalog = Articles->getByPkey($catid)
#        or die "Catalog $catid not found";

#      my $release = param('release');
#      defined $release
#        or $release = "01/01/2000";
#      use BSE::Util::Valid qw/valid_date/;
#      $release eq '' or valid_date($release)
#        or die "Invalid release date";
#      my $expire = param('expire');
#      defined $expire
#        or $expire = '31/12/2999';
#      $expire eq '' or valid_date($expire)
#        or die "Invalid expire data";
  
#      my $newentry = 
#        BSE::Admin::StepParents->add($catalog, $product, $release, $expire);
#    };
#    $@ and product_edit_refresh($productid, $@, 'step');

#    return product_edit_refresh($productid, '', 'step');
#  }

#  sub del_stepcat {
#    require 'BSE/Admin/StepParents.pm';
#    my $productid = param('id');
#    defined $productid
#      or return product_list("No id supplied to del_stepcat");
#    int($productid) eq $productid+0
#      or return product_list("Invalid product id supplied to del_stepcat");
#    my $product = Products->getByPkey($productid)
#      or return product_list("Cannot find product id $productid");

#    my $catid = param('stepcat');
#    defined($catid)
#      or return shop_redirect("?id=$productid&edit_product=1&message=No+stepcat+supplied+to+add_stepcat#step");
#    int($catid) eq $catid
#      or return shop_redirect("?id=$productid&edit_product=1&message=Invalid+stepcat+supplied+to+add_stepcat#step");
#    my $catalog = Articles->getByPkey($catid)
#      or return shop_redirect("?id=$productid&edit_product=1&message=".CGI::escape("Catalog+$catid+not+found")."#step");

#    eval {
#      BSE::Admin::StepParents->del($catalog, $product);
#    };
#    $@ and return shop_redirect("?id=$productid&edit_product=1&message=".CGI::escape($@)."#step");

#    return shop_redirect("?id=$productid&edit_product=1#step");
#  }

#  sub save_stepcats {
#    require 'BSE/Admin/StepParents.pm';
#    my $productid = param('id');
#    defined $productid
#      or return product_list("No id supplied to del_stepcat");
#    int($productid) eq $productid+0
#      or return product_list("Invalid product id supplied to del_stepcat");
#    my $product = Products->getByPkey($productid)
#      or return product_list("Cannot find product id $productid");

#    my @stepcats = OtherParents->getBy(childId=>$product->{id});
#    my %stepcats = map { $_->{parentId}, $_ } @stepcats;
#    my %datedefs = ( release => '2000-01-01', expire=>'2999-12-31' );
#    for my $stepcat (@stepcats) {
#      for my $name (qw/release expire/) {
#        my $date = param($name.'_'.$stepcat->{parentId});
#        if (defined $date) {
#  	if ($date eq '') {
#  	  $date = $datedefs{$name};
#  	}
#  	elsif (valid_date($date)) {
#  	  use BSE::Util::SQL qw/date_to_sql/;
#  	  $date = date_to_sql($date);
#  	}
#  	else {
#  	  product_edit_refresh($productid, "Invalid date '$date'");
#  	}
#  	$stepcat->{$name} = $date;
#        }
#      }
#      eval {
#        $stepcat->save();
#      };
#      $@ and product_edit_refresh($productid, $@);
#    }
#    product_edit_refresh($productid, $@);
#  }

#####################
# utilities
# perhaps some of these belong in a class...

sub product_edit_refresh {
  my ($productid, $message, $name) = @_;

  my $url = '?edit_product=1&id='.$productid;
  $url .= '&message='.CGI::escape($message) if $message;
  $url .= "#$name" if $name;

  shop_redirect($url);
}

sub page {
  my ($which, $acts, $iter) = @_;

  BSE::Template->show_page('admin/'.$which, $cfg, $acts);
}

sub shop_url {
  my $url = shift;
  "$ENV{SCRIPT_NAME}$url"
}

sub shop_redirect {
  my $url = shift;
  print "Content-Type: text/html\n";
  print qq!Refresh: 0; url=\"!,shop_url($url),qq!"\n\n<html></html>\n!;
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

# convert an epoch time to sql format
sub epoch_to_sql_datetime {
  use POSIX 'strftime';
  my ($time) = @_;

  return strftime('%Y-%m-%d %H:%M', localtime $time);
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
