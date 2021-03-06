package BSE::Edit::Product;
use strict;
use base 'BSE::Edit::Article';
use BSE::TB::Products;
use HTML::Entities;
use BSE::Template;
use BSE::Util::Iterate;
use BSE::Util::HTML;
use BSE::CfgInfo 'product_options';
use BSE::Util::Tags qw(tag_hash tag_article);
use constant PRODUCT_CUSTOM_FIELDS_CFG => "product custom fields";

our $VERSION = "1.016";

=head1 NAME

BSE::Edit::Product - tags and actions for editing BSE products

=head1 SYNOPSIS

  http://www.example.com/cgi-bin/admin/add.pl ...

=head1 DESCRIPTION

Article editor subclass for editing Products.

=cut

my %money_fields =
  (
   retailPrice => "Retail price",
   wholesalePrice => "Wholesale price",
   gst => "GST",
  );

sub generator { 'BSE::Generate::Product' }

sub _make_dummy_article {
  my ($self, $article) = @_;

  require BSE::DummyProduct;
  return bless $article, "BSE::DummyProduct";
}

sub base_template_dirs {
  return ( "products" );
}

sub extra_templates {
  my ($self, $article) = @_;

  my @extras = $self->SUPER::extra_templates($article);
  push @extras, 'shopitem.tmpl' 
    if grep -f "$_/shopitem.tmpl", 
      BSE::Template->template_dirs($self->{cfg});

  my $extras = $self->{cfg}->entry('products', 'extra_templates');
  push @extras, grep /\.(tmpl|html)$/i, split /,/, $extras
    if $extras;

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

sub iter_subs {
  require BSE::TB::Subscriptions;
  BSE::TB::Subscriptions->all;
}

sub iter_option_values {
  my ($self, $rcurrent_option, $args) = @_;

  $$rcurrent_option
    or return;

  return $$rcurrent_option->values;
}

sub tag_hash_mbcs {
  my ($object, $args) = @_;

  my $value = $object->{$args};
  defined $value or $value = '';
  if ($value =~ /\cJ/ && $value =~ /\cM/) {
    $value =~ tr/\cM//d;
  }
  escape_html($value, '<>&"');
}

sub tag_dboptionvalue_move {
  my ($self, $req, $article, $rvalues, $rindex, $args) = @_;

  $$rindex >= 0 && $$rindex < @$rvalues
    or return "** dboptionvalue_move only in dboption_values iterator **";

  my $my_id = $rvalues->[$$rindex]{id};
  my $base_url = "$ENV{SCRIPT_NAME}?id=$article->{id}&value_id=$my_id&_csrfp=".$req->get_csrf_token("admin_move_option_value") . "&";

  my $t = $req->cgi->param('_t');
  $t && $t =~ /^\w+$/
    and $base_url .= "_t=$t&";

  my $up_url = '';
  if ($$rindex > 0) {
    $up_url = $base_url . "a_option_value_moveup=1";
  }
  my $down_url = '';
  if ($$rindex < $#$rvalues) {
    $down_url = $base_url . "a_option_value_movedown=1";
  }

  my $refresh = $self->refresh_url($article, $req->cgi);

  require BSE::Arrows;
  return BSE::Arrows::make_arrows($req->cfg, $down_url, $up_url, $refresh, $args, id => $my_id, id_prefix => "prodoptvaluemove");
}

sub tag_dboption_move {
  my ($self, $req, $article, $roptions, $rindex, $args) = @_;

  $$rindex >= 0 && $$rindex < @$roptions
    or return "** dboption_move only in dboptions iterator **";

  my $my_id = $roptions->[$$rindex]{id};
  my $base_url = "$ENV{SCRIPT_NAME}?id=$article->{id}&option_id=$my_id&_csrfp=".$req->get_csrf_token("admin_move_option") . "&";

  my $t = $req->cgi->param('_t');
  $t && $t =~ /^\w+$/
    and $base_url .= "_t=$t&";

  my $up_url = '';
  if ($$rindex > 0) {
    $up_url = $base_url . "a_option_moveup=1";
  }
  my $down_url = '';
  if ($$rindex < $#$roptions) {
    $down_url = $base_url . "a_option_movedown=1";
  }

  my $refresh = $self->refresh_url($article, $req->cgi);

  require BSE::Arrows;
  return BSE::Arrows::make_arrows($req->cfg, $down_url, $up_url, $refresh, $args, id => $my_id, id_prefix => "prodoptmove");
}

sub tag_tier_price {
  my ($self, $rtier, $rprices, $product) = @_;

  unless ($rprices->{loaded}) {
    %$rprices = map { $_->tier_id => $_ } $product->prices
      if $product->{id};
    $rprices->{loaded} = 1;
  }

  $$rtier or return '** no current tier **';

  exists $rprices->{$$rtier->id}
    or return '';

  return $rprices->{$$rtier->id}->retailPrice;
}

sub save_more {
  my ($self, $req, $article, $data) = @_;

  $self->_save_price_tiers($req, $article, $data);
  $self->SUPER::save_more($req, $article, $data);
}

sub save_new_more {
  my ($self, $req, $article, $data) = @_;

  $self->_save_price_tiers($req, $article, $data);
  $self->SUPER::save_new_more($req, $article, $data);
}

sub _save_price_tiers {
  my ($self, $req, $article, $data) = @_;

  $data->{save_pricing_tiers}
    or return;

  $req->user_can('edit_field_edit_retailPrice', $article)
    or return;

  my @tiers = BSE::TB::Products->pricing_tiers;
  my %prices;
  for my $tier (@tiers) {
    my $key = "tier_price_" . $tier->id;
    if (exists $data->{$key} && $data->{$key} =~ /\S/) {
      $prices{$tier->id} = $data->{$key} * 100;
    }
  }
  $article->set_prices(\%prices);
}

sub save_columns {
  my ($self, $table_object) = @_;

  my @cols = $self->SUPER::save_columns($table_object);
  my @tiers = BSE::TB::Products->pricing_tiers;
  if (@tiers) {
    push @cols, "save_pricing_tiers";
    push @cols, map { "tier_price_" . $_->id } @tiers;
  }

  return @cols;
}

sub iter_dboptions {
  my ($self, $article) = @_;

  $article->{id}
    or return;

  return $article->db_options;
}

=head1 Edit tags

These a tags available on admin/edit_* pages specific to products.

=over

=item *

product I<field> - display the given field from the product being edited.

=item *

iterator begin dboptions ... dboption I<field> ... iterator end dboptions

- iterate over the existing database stored options for the product

=item *

dboption_move - display arrows to move the current dboption.  The span
for the arrows is given an id of "prodoptmoveI<option-id>" by default.

=item *

iterator begin dboptionvalues ... dboptionvalue I<field> ... iterator end dboptionvalues

- iterate over the values for the current dboption

=item *

dboptionvalue_move - display arrows to move the current dboption.  The
span for the arrows is given an id of "prodoptvaluemoveI<value-id>"
by default.

=item *

dboptionsjson - returns the product options as JSON.

=item *

iterator begin price_tiers ... price_tier I<field> ... iterator end price_tiers

Iterate over the configured price tiers.

=item *

tier_price

Return the price at the current price_tier.  Returns an empty string
if there's no price at this tier.

=back

=cut

sub low_edit_tags {
  my ($self, $acts, $req, $article, $articles, $msg, $errors) = @_;

  my $product_opts = product_options($req->cfg);

  my $cfg = $req->cfg;
  my $mbcs = $cfg->entry('html', 'mbcs', 0);
  my $tag_hash = $mbcs ? \&tag_hash_mbcs : \&hash_tag;
  my $current_option;
  my @dboptions;
  my $dboption_index;
  my @dboption_values;
  my $dboption_value_index;
  my $current_option_value;
  my $it = BSE::Util::Iterate->new;
  my @tiers;
  my $price_tier;
  my %prices;
  $req->set_variable(product => $article);
  return 
    (
     product => [ \&tag_article, $article, $cfg ],
     $self->SUPER::low_edit_tags($acts, $req, $article, $articles, $msg,
				$errors),
     alloptions => join(",", sort keys %$product_opts),
     $it->make_iterator
     ([ \&iter_subs, $req ], 'subscription', 'subscriptions'),
     $it->make
     (
      single => "dboption",
      plural => "dboptions",
      store => \$current_option,
      data => \@dboptions,
      index => \$dboption_index,
      code => [ iter_dboptions => $self, $article ],
     ),
     dboption_move =>
     [
      tag_dboption_move =>
      $self, $req, $article, \@dboptions, \$dboption_index
     ],
     $it->make
     (
      single => "dboptionvalue",
      plural => "dboptionvalues",
      data => \@dboption_values,
      index => \$dboption_value_index,
      store => \$current_option_value,
      code => [ iter_option_values => $self, \$current_option ],
      nocache => 1,
     ),
     dboptionsjson => [ tag_dboptionsjson => $self, $article ],
     dboptionvalue_move => 
     [
      tag_dboptionvalue_move =>
      $self, $req, $article, \@dboption_values, \$dboption_value_index
     ],
     $it->make
     (
      single => "price_tier",
      plural => "price_tiers",
      code => [ pricing_tiers => "BSE::TB::Products" ],
      data => \@tiers,
      store => \$price_tier,
     ),
     tier_price => [ tag_tier_price => $self, \$price_tier, \%prices, $article ],
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
			     'admin/edit_product');
}

sub validate_parent {
  my ($self, $data, $articles, $parent, $rmsg) = @_;

  my $shopid = $self->{cfg}->entryErr('articles', 'shop');
  unless ($parent && 
	  $parent->{generator} eq 'BSE::Generate::Catalog') {
    $$rmsg = "Products must be in a catalog (not $parent->{generator})";
    return;
  }

  return $self->SUPER::validate_parent($data, $articles, $parent, $rmsg);
}

sub _validate_common {
  my ($self, $data, $articles, $errors) = @_;

  $self->SUPER::_validate_common($data, $articles, $errors);

  for my $col (keys %money_fields) {
    my $value = $data->{$col};
    defined $value or next;
    unless ($value =~ /^\d+(\.\d{1,2})?\s*/) {
      $errors->{$col} = "$money_fields{$col} invalid";
    }
  }

  if (defined $data->{options}) {
    my $avail_options = product_options($self->{cfg});
  
    my @bad_opts = grep !$avail_options->{$_}, 
      split /,/, $data->{options};
    if (@bad_opts) {
      $errors->{options} = "Bad product options '". join(",", @bad_opts)."' entered";
    }
  }

  my @subs;
  for my $sub_field (qw(subscription_id subscription_required)) {
    my $value = $data->{$sub_field};
    defined $value or next;
    if ($value ne '-1') {
      require BSE::TB::Subscriptions;
      @subs = BSE::TB::Subscriptions->all unless @subs;
      unless (grep $_->{subscription_id} == $value, @subs) {
	$errors->{$sub_field} = "Invalid $sub_field value";
      }
    }
  }
  if (defined $data->{subscription_period}) {
    my $sub = $data->{subscription_id};
    if ($data->{subscription_period} !~ /^\d+$/) {
      $errors->{subscription_period} = "Invalid subscription period, it must be the number of months to subscribe";
    }
    elsif ($sub != -1 && $data->{subscription_period} < 1) {
      $errors->{subscription_period} = "Subscription period must be 1 or more when a subscription is selected";
    }
  }
  if (defined $data->{subscription_usage}) {
    unless ($data->{subscription_usage} =~ /^[123]$/) {
      $errors->{subscription_usage} = "Invalid subscription usage";
    }
  }

  if ($data->{save_pricing_tiers}) {
    my @tiers = BSE::TB::Products->pricing_tiers;
    for my $tier (@tiers) {
      my $key = "tier_price_" . $tier->id;
      my $value = $data->{$key};
      defined $value or next;
      if ($value =~ /\S/ && $value !~ /^\d+(\.\d{1,2})?\s*/) {
	$errors->{$key} = 'Pricing tier "' . $tier->description . '" price invalid';
      }
    }
  }

  return !keys %$errors;
}

sub validate {
  my ($self, $data, $articles, $errors) = @_;

  my $ok = $self->SUPER::validate($data, $articles, $errors);
  $self->_validate_common($data, $articles, $errors);

  for my $field (qw(title)) {
    unless ($data->{$field} =~ /\S/) {
      $errors->{$field} = "No $field entered";
    }
  }

  return $ok && !keys %$errors;
}

sub validate_old {
  my ($self, $article, $data, $articles, $errors) = @_;

  $self->SUPER::validate_old($article, $data, $articles, $errors)
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
      grep $_->{generator} eq 'BSE::Generate::Catalog', 
      $articles->getBy(parentid=>$id);
  }
  unless ($shop->{generator} eq 'BSE::Generate::Catalog') {
    shift @values;
    delete $labels{$shopid};
  }
  return (\@values, \%labels);
}

sub table_object {
  my ($self, $articles) = @_;

  'BSE::TB::Products';
}

sub get_article {
  my ($self, $articles, $article) = @_;

  return BSE::TB::Products->getByPkey($article->{id});
}

sub default_link_path {
  my ($self, $article) = @_;

  $self->{cfg}->entry('uri', 'shop', '/shop');
}

sub make_link {
  my ($self, $article) = @_;

  $article->is_linked
    or return "";

# Modified by adrian
  my $urlbase = '';
  if ($self->{cfg}->entry('shop', 'secureurl_articles', 1)) {
    $urlbase = $self->{cfg}->entryVar('site', 'secureurl');
  }
# end adrian

  if ($article->is_dynamic) {
    (my $extra = $article->title) =~ tr/A-Za-z0-9/-/sc;
    return "$urlbase/cgi-bin/page.pl?page=$article->{id}&title=".escape_uri($extra);
  }

  my $shop_uri = $self->link_path($article);
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
  if (exists $src->{description} && length $src->{description}) {
    if ($data->{id}) {
      if ($req->user_can('edit_field_edit_description', $data)) {
	$data->{description} = $src->{description};
      }
    }
  }
  if (exists $src->{product_code} && length $src->{product_code}) {
    if ($data->{id}) {
      if ($req->user_can('edit_field_edit_product_code', $data)) {
	$data->{product_code} = $src->{product_code};
      }
    }
  }
  for my $field (qw(options subscription_id subscription_period
                    subscription_usage subscription_required
                    weight length width height)) {
    if (exists $src->{$field}) {
      $data->{$field} = $src->{$field};
    }
    elsif ($data == $src) {
      # use the default
      $data->{$field} = $self->default_value($req, $data, $field);
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

  my $template = $cfg->entry('products', 'template');
  return $template
    if $template && grep $_ eq $template, @$templates;

  return $self->SUPER::default_template($article, $cfg, $templates);
}

sub flag_sections {
  my ($self) = @_;

  return ( 'product flags', $self->SUPER::flag_sections );
}

sub shop_article { 1 }

my %defaults =
  (
   options => '',
   description => '',
   subscription_id => -1,
   subscription_required => -1,
   subscription_period => 1,
   subscription_usage => 3,
   leadTime => 0,
   retailPrice => 0,
   wholesalePrice => 0,
   gst => 0,
   product_code => '',
   weight => 0,
   length => 0,
   height => 0,
   width => 0,
  );

sub default_value {
  my ($self, $req, $article, $col) = @_;

  my $value = $self->SUPER::default_value($req, $article, $col);
  defined $value and return $value;

  exists $defaults{$col} and return $defaults{$col};

  return;
}

sub type_default_value {
  my ($self, $req, $col) = @_;

  my $value = $req->cfg->entry('product defaults', $col);
  defined $value and return $value;

  return $self->SUPER::type_default_value($req, $col);
}

my %option_fields =
  (
   name =>
   {
    description => "Option name",
    required => 1,
    rules => "dh_one_line",
    maxlength => 255,
   },
   value1 =>
   {
    description => "Value 1",
    rules => "dh_one_line",
    maxlength => 255,
   },
   value2 =>
   {
    description => "Value 2",
    rules => "dh_one_line",
    maxlength => 255,
   },
   value3 =>
   {
    description => "Value 3",
    rules => "dh_one_line",
    maxlength => 255,
   },
   value4 =>
   {
    description => "Value 4",
    rules => "dh_one_line",
    maxlength => 255,
   },
   value5 =>
   {
    description => "Value 5",
    rules => "dh_one_line",
    maxlength => 255,
   },
  );

=head1 Targets

Actions you can request from add.pl for products.

=over

=item a_add_option

Add a new product option.

On failure perform a service error.

Requires _csrfp for admin_add_option

For Ajax requests (or with a _ parameter) returns JSON like:

  { 
   success: 1,
   option: { <option data> },
   values: [ { value data }, { value data }, ... ]
  }

Parameters:

=over

=item *

id - Article id

=item *

name - Name of the option (required)

=item *

value1 .. value5 - if any of these are non-blank they are added to the
option as values.

=back

Permission required: bse_edit_prodopt_add 

=cut

sub req_add_option {
  my ($self, $req, $article, $articles, $msg, $errors) = @_;

  $req->check_csrf('admin_add_option')
    or return $self->csrf_error($req, $article, "admin_add_option", "Add Product Option");

  $req->user_can(bse_edit_prodopt_add => $article)
    or return $self->_service_error($req, $article, $articles, "Insufficient product access to add options");

  my %errors;
  $req->validate(fields => \%option_fields,
		 errors => \%errors);
  keys %errors
    and return $self->_service_error($req, $article, $articles, undef, 
				     \%errors);

  my $cgi = $req->cgi;
  require BSE::TB::ProductOptions;
  require BSE::TB::ProductOptionValues;
  my $option = BSE::TB::ProductOptions->make
    (
     product_id => $article->{id},
     name => scalar($cgi->param('name')),
     display_order => time,
    );

  my $order = time;
  my @values;
  for my $value_key (sort grep /^value/, keys %option_fields) {
    my ($value) = $cgi->param($value_key);
    if (defined $value && $value =~ /\S/) {
      my $entry = BSE::TB::ProductOptionValues->make
	(
	 product_option_id => $option->{id},
	 value => $value,
	 display_order => $order,
	);
      push @values, $entry;
      ++$order;
    }
  }

  $req->is_ajax
    and return $req->json_content
      (
       success => 1,
       option => $option->data_only,
       values => [ map $_->data_only, @values ]
      );

  return $self->refresh($article, $cgi, undef, "Option added");
}

my %option_id =
  (
   option_id =>
   {
    rules => "required;positiveint",
   },
  );

sub _get_option {
  my ($self, $req, $article, $errors) = @_;

  my $option;
  my $cgi = $req->cgi;
  $req->validate(fields => \%option_id,
		 errors => $errors);
  my @option_ids = $cgi->param("option_id");
  unless ($errors->{option_id}) {
    @option_ids == 1
      or $errors->{option_id} = "This request accepts only one option_id";
  }
  unless ($errors->{option_id}) {
    require BSE::TB::ProductOptions;
    $option = BSE::TB::ProductOptions->getByPkey($cgi->param("option_id"));
    $option
      or $errors->{option_id} = "Unknown option id";
  }
  unless ($errors->{option_id}) {
    $option->{product_id} = $article->{id}
      or $errors->{option_id} = "Option doesn't belong to this product";
  }
  $errors->{option_id}
    and return;

  return $option;
}

sub _common_option {
  my ($self, $template, $req, $article, $articles, $msg, $errors) = @_;

  my %errors;
  my $option = $self->_get_option($req, $article, \%errors);
  keys %errors
    and return $self->_service_error($req, $article, $articles, undef, \%errors);

  my $it = BSE::Util::Iterate->new;
  my %acts;
  %acts =
    (
     $self->low_edit_tags(\%acts, $req, $article, $articles, $msg, $errors),
     option => [ \&tag_hash, $option ],
     $it->make
     (
      single => "dboptionvalue",
      plural => "dboptionvalues",
      code => [ iter_option_values => $self, \$option ],
     ),
    );

  return $req->dyn_response($template, \%acts);
}

=item a_edit_option

Produce a form to edit the given option.

Parameters:

=over

=item *

id - article id

=item *

option_id - option id.  This must belong to the product identified by
id.

=back

Template: admin/prodopt_edit

Permission required: bse_edit_prodopt_edit

=cut

sub req_edit_option {
  my ($self, $req, $article, $articles, $msg, $errors) = @_;

  $req->user_can(bse_edit_prodopt_edit => $article)
    or return $self->_service_error($req, $article, $articles, "Insufficient product access to edit options");

  return $self->_common_option('admin/prodopt_edit', $req, $article, 
			       $articles, $msg, $errors);
}

my %option_name =
  (
   name =>
   {
    description => "Option name",
    rules => "required;dh_one_line",
    maxlength => 255,
   },
   default_value =>
   {
    description => "Default Value",
    rules => "positiveint"
   }
  );

my %option_value =
  (
   description => "Value",
   rules => "required;dh_one_line",
   maxlength => 255,
  );

=item a_save_option

Saves changes to an option.

On failure perform a service error.

Requires _csrfp for admin_save_option

For Ajax requests (or with a _ parameter), returns JSON like:

  { 
   success: 1,
   option: { <option data> },
   values: [ { value data, value data, ... } ]
  }

Parameters:

=over

=item *

id - article id

=item *

option_id - id of the option to save, must belong to the product
identified by id.

=item *

name - new value for the name field

=item *

default_value - id of the default value

=item *

save_enabled - if supplied and true, set enabled from the enabled
parameter.

=item *

enabled - If supplied and true, enable the option, otherwise disable
it.  Ignored unless save_enabled is true.

=item *

valueI<value-id> - set the displayed value for the value record
identified by I<value-id>.  If these aren't supplied the values aren't
changed.

=back

Permission required: bse_edit_prodopt_save

=cut

sub req_save_option {
  my ($self, $req, $article, $articles) = @_;

  my $cgi = $req->cgi;

  $req->check_csrf("admin_save_option")
    or return $self->csrf_error($req, $article, "admin_save_option", "Save Product Option");

  $req->user_can(bse_edit_prodopt_edit => $article)
    or return $self->_service_error($req, $article, $articles, "Insufficient product access to edit options");

  my %errors;
  my $option = $self->_get_option($req, $article, \%errors);
  keys %errors
    and return $self->_service_error($req, $article, $articles, undef, \%errors, 'FIELD', "req_edit_option");
  $req->validate(fields => \%option_name,
		 errors => \%errors);
  my @values = $option->values;
  my %fields = map {; "value$_->{id}" => \%option_value } @values;
  $req->validate(fields => \%fields,
		 errors => \%errors,
		 optional => 1);
  my $default_value = $cgi->param('default_value');
  if (!$errors{default_value} && $default_value) {
    grep $_->{id} == $default_value, @values
      or $errors{default_value} = "Unknown value selected as default";
  }

  $DB::single = 1;
  my @new_values;
  my $index = 1;
  while ($index < 10 && defined $cgi->param("newvalue$index")) {
    my $field = "newvalue$index";
    my $value = $cgi->param($field);
    $req->validate(fields => { $field => \%option_value },
		   errors => \%errors);
    push @new_values, $value;

    ++$index;
  }

  keys %errors
    and return $self->_service_error($req, $article, $articles, undef, \%errors, "FIELD", "req_edit_option");

  my $name = $cgi->param("name");
  defined $name
    and $option->set_name($name);
  defined $default_value
    and $option->set_default_value($default_value);
  if ($cgi->param("save_enabled")) {
    my $enabled = $cgi->param("enabled") ? 1 : 0;
    $option->set_enabled($enabled);
  }
  $option->save;
  for my $value (@values) {
    my $new_value = $cgi->param("value$value->{id}");
    if (defined $new_value && $new_value ne $value->value) {
      $value->set_value($new_value);
      $value->save;
    }
  }
  my $order = @values ? $values[-1]->display_order : time;
  for my $value (@new_values) {
    BSE::TB::ProductOptionValues->make
	(
	 product_option_id => $option->id,
	 value => $value,
	 display_order => ++$order,
	);
  }

  $req->is_ajax
    and return $req->json_content
      (
       success => 1,
       option => $option->data_only,
       values => [ map $_->data_only, @values ],
      );

  return $self->refresh($article, $req->cgi, undef,
			"Option '" . $option->name . "' saved");
}

=item a_delconf_option

Produce a form to confirm deletion of the given option.

Parameters:

=over

=item *

id - article id

=item *

option_id - option id.  This must belong to the product identified by
id.

=back

Template: admin/prodopt_delete

=cut

sub req_delconf_option {
  my ($self, $req, $article, $articles, $msg, $errors) = @_;

  $req->user_can(bse_edit_prodopt_delete => $article)
    or return $self->_service_error($req, $article, $articles, "Insufficient product access to delete options");

  return $self->_common_option('admin/prodopt_delete', $req, $article, 
			       $articles, $msg, $errors);
}

=item a_delete_option

Delete the given option.

On failure perform a service error.

Requires _csrfp for admin_delete_option

For Ajax requests (or with a _ parameter), returns JSON like:

  { 
   success: 1,
  }

Permission required: bse_edit_prodopt_delete

=cut

sub req_delete_option {
  my ($self, $req, $article, $articles) = @_;

  $req->check_csrf("admin_delete_option")
    or return $self->csrf_error($req, $article, "admin_delete_option", "Delete Product Option");

  $req->user_can(bse_edit_prodopt_delete => $article)
    or return $self->_service_error($req, $article, $articles, "Insufficient product access to delete options");

  my %errors;
  my $option = $self->_get_option($req, $article, \%errors);
  keys %errors
    and return $self->_service_error($req, $article, $articles, undef, \%errors);
  my @values = $option->values;

  for my $value (@values) {
    $value->remove;
  }
  $option->remove;

  $req->is_ajax
    and return $req->json_content
      (
       success => 1
      );

  return $self->refresh($article, $req->cgi, undef, "Option deleted");
}


my %add_option_value_fields =
  (
   option_id =>
   {
    description => "Option id",
    rules => "required;positiveint",
   },
   value =>
   {
    description => "Value",
    rules => "required;dh_one_line",
    maxlength => 255,
   },
  );

=item a_add_option_value

Add a value to a product option.

On failure perform a service error, see BSE::Edit::Article::_service_error.

Requires _csrfp for admin_add_option_value

For Ajax requests returns JSON like

 { success: 1, value: (valueobject) }

Standard redirect on success otherwise.

Parameters:

=over

=item *

id - article id

=item *

option_id - id of the option to add the value to

=item *

value - text of the value to add.

=back

Permission required: bse_edit_prodopt_edit

=cut

sub req_add_option_value {
  my ($self, $req, $article, $articles, $msg, $errors) = @_;

  $req->check_csrf("admin_add_option_value")
    or return $self->csrf_error($req, $article, "admin_add_option_value", "Add Product Option Value");

  $req->user_can(bse_edit_prodopt_edit => $article)
    or return $self->_service_error($req, $article, $articles, "Insufficient product access to edit options");

  my %errors;
  $req->validate(fields => \%add_option_value_fields,
		 errors => \%errors);
  my $option;
  my $cgi = $req->cgi;
  unless ($errors{option_id}) {
    require BSE::TB::ProductOptions;
    $option = BSE::TB::ProductOptions->getByPkey($cgi->param("option_id"));
    defined $option && $option->{product_id}
      or $errors{option_id} = "Bad option id - either unknown or for a different product";
  }
  keys %errors
    and return $self->_service_error($req, $article, $articles, undef, \%errors);

  my $value = $cgi->param("value");
  require BSE::TB::ProductOptionValues;
  my $entry = BSE::TB::ProductOptionValues->make
    (
     product_option_id => $option->{id},
     value => $value,
     display_order => time,
    );

  $req->is_ajax
    and return $req->json_content
      (
       success => 1,
       value => $entry->data_only
      );

  return $self->refresh($article, $cgi, undef, "Value added");
}


my %option_value_id =
  (
   value_id =>
   {
    rules => "required;positiveint",
   },
  );

sub _get_option_value {
  my ($self, $req, $article, $errors) = @_;

  my $option_value;
  my $cgi = $req->cgi;
  $req->validate(fields => \%option_value_id,
		 errors => $errors);
  unless ($errors->{value_id}) {
    require BSE::TB::ProductOptionValues;
    $option_value = BSE::TB::ProductOptionValues->getByPkey($cgi->param("value_id"));
    $option_value
      or $errors->{value_id} = "Unknown option value id";
  }
  my $option;
  unless ($errors->{value_id}) {
    $option = $option_value->option;
    defined $option && $option->{product_id} == $article->{id}
      or $errors->{value_id} = "Value has no option or doesn't belong to the product";
  }

  $errors->{value_id}
    and return;

  return wantarray ? ( $option_value, $option ) : $option_value ;
}

sub _common_option_value {
  my ($self, $template, $req, $article, $articles, $msg, $errors) = @_;

  my %errors;
  my ($option_value, $option) = $self->_get_option_value($req, $article, \%errors);
  keys %errors
    and return $self->_service_error($req, $article, $articles, undef, \%errors);

  my %acts;
  %acts =
    (
     $self->low_edit_tags(\%acts, $req, $article, $articles, $msg, $errors),
     option_value => [ \&tag_hash, $option_value ],
     option => [ \&tag_hash, $option ],
    );

  return $req->dyn_response($template, \%acts);
}

=item a_edit_option_value

Displays a form to edit the value for a given option.

Parameters:

=over

=item *

id - id of the product

=item *

value_id - id of he product option value to edit, must belong to the
given product.

=back

Template: admin/prodopt_value_edit

Permission required: bse_edit_prodopt_edit

=cut

sub req_edit_option_value {
  my ($self, $req, $article, $articles, $msg, $errors) = @_;

  $req->user_can(bse_edit_prodopt_edit => $article)
    or return $self->_service_error($req, $article, $articles, "Insufficient product access to edit options");

  return $self->_common_option_value('admin/prodopt_value_edit', $req,
				     $article, $articles, $msg, $errors);
}

my %save_option_value_fields =
  (
   value => 
   {
    rules => "required;dh_one_line",
    maxlength => 255,
   },
  );

=item a_save_option_value

Saves changes to an option.

On failure perform a service error.

Requires _csrfp for admin_save_option_value

For Ajax requests (or with a _ parameter), returns JSON like:

  { 
   success: 1,
   value: { value data }
  }

Parameters:

=over

=item *

id - article id

=item *

value_id - id of the value to save, must belong to the product
identified by id.

=item *

value - new displayed value for the option value.

=back

Permission required: bse_edit_prodopt_edit

=cut

sub req_save_option_value {
  my ($self, $req, $article, $articles, $msg, $errors) = @_;

  $req->check_csrf("admin_save_option_value")
    or return $self->csrf_error($req, $article, "admin_save_option_value", "Save Product Option Value");

  $req->user_can(bse_edit_prodopt_edit => $article)
    or return $self->_service_error($req, $article, $articles, "Insufficient product access to edit options");

  my %errors;
  $req->validate(fields => \%save_option_value_fields,
		 errors => \%errors);
  my $option_value = $self->_get_option_value($req, $article, \%errors);
  keys %errors
    and return $self->_service_error($req, $article, $articles, undef, \%errors);

  my $cgi = $req->cgi;
  $option_value->{value} = $cgi->param("value");
  $option_value->save;

  $req->is_ajax
    and return $req->json_content
      (
       success => 1,
       value => $option_value->data_only
      );

  return $self->refresh($article, $cgi, undef, "Value saved");
}

=item a_confdel_option_value

Displays a page confirming deletion of a product option value.

Parameters:

=over

=item *

id - article id

=item *

value_id - option value id

=back

Template: admin/prodopt_value_delete

Permission required: bse_edit_prodopt_edit

=cut

sub req_confdel_option_value {
  my ($self, $req, $article, $articles, $msg, $errors) = @_;

  $req->user_can(bse_edit_prodopt_edit => $article)
    or return $self->_service_error($req, $article, $articles, "Insufficient product access to edit options");

  return $self->_common_option_value('admin/prodopt_value_delete', $req,
				     $article, $articles, $msg, $errors);
}

=item a_delete_option_value

Deletes a product option.

On failure perform a service error.

Requires _csrfp for admin_delete_option_value

For Ajax requests (or with a _ parameter), returns JSON like:

  { 
   success: 1,
  }

Parameters:

=over

=item *

id - article id

=item *

value_id - id of the value to delete, must belong to the product
identified by id.

=back

Permission required: bse_edit_prodopt_edit

=cut

sub req_delete_option_value {
  my ($self, $req, $article, $articles, $msg, $errors) = @_;

  $req->check_csrf("admin_delete_option_value")
    or return $self->csrf_error($req, $article, "admin_delete_option_value", "Delete Product Option Value");

  $req->user_can(bse_edit_prodopt_edit => $article)
    or return $self->_service_error($req, $article, $articles, "Insufficient product access to edit options");

  my %errors;
  my $option_value = $self->_get_option_value($req, $article, \%errors);
  keys %errors
    and return $self->_service_error($req, $article, $articles, undef, \%errors);

  $option_value->remove;

  $req->is_ajax
    and return $req->json_content
      (
       success => 1
      );

  return $self->refresh($article, $req->cgi, undef, "Value removed");
}

sub tag_dboptionsjson {
  my ($self, $article) = @_;

  my @result;
  my @options = $article->db_options;
  my @opt_cols = BSE::TB::ProductOption->columns;
  for my $option (@options) {
    my $entry = $option->data_only;
    $entry->{values} = [ map $_->data_only, $option->values ];
    push @result, $entry;
  }

  require JSON;
  my $json = JSON->new;
  return $json->encode(\@result);
}

sub _option_move {
  my ($self, $req, $article, $articles, $direction) = @_;

  $req->check_csrf("admin_move_option")
    or return $self->csrf_error($req, $article, "admin_move_option", "Move Product Option");

  $req->user_can(bse_edit_prodopt_move => $article)
    or return $self->_service_error($req, $article, $articles, "Insufficient product access to move options");

  my %errors;
  my $option = $self->_get_option($req, $article, \%errors);
  keys %errors
    and return $self->_service_error($req, $article, $articles, undef, \%errors);
  my @options = $article->db_options;
  my ($index) = grep $options[$_]{id} == $option->{id}, 0 .. $#options
    or return $self->_service_error($req, $article, $articles, "Unknown option id");

  $options[$index] = $option;

  my $other_index = $index + $direction;
  $other_index >= 0 && $other_index < @options
    or return $self->_service_error($req, $article, $articles, "Can't move option beyond end");

  my $other = $options[$other_index];

  ($option->{display_order}, $other->{display_order}) =
    ($other->{display_order}, $option->{display_order});
  $option->save;
  $other->save;

  if ($req->is_ajax) {
    @options = sort { $a->{display_order} <=> $b->{display_order} } @options;
    return return $req->json_content
      (
       success => 1,
       order => [ map $_->{id}, @options ]
      );
  }

  return $self->refresh($article, $req->cgi, undef, "Option moved");
}

=item a_option_moveup

=item a_option_movedown

Move a product option up/down through the options for a product.

On failure perform a service error.

Requires _csrfp for admin_move_option

For Ajax requests (or with a _ parameter), returns JSON like:

  {
   success: 1,
   order: [ list of option ids ]
  }

Parameters:

=over

=item *

id - article id

=item *

option_id - option id.  This must belong to the product identified by
id.

=back

Permission required: bse_edit_prodopt_move

=cut

sub req_option_moveup {
  my ($self, $req, $article, $articles) = @_;

  return $self->_option_move($req, $article, $articles, -1);
}

sub req_option_movedown {
  my ($self, $req, $article, $articles) = @_;

  return $self->_option_move($req, $article, $articles, 1);
}

=item a_option_reorder

Move a product option up/down through the options for a product.

On failure perform a service error.

Requires _csrfp for admin_move_option

For Ajax requests (or with a _ parameter), returns JSON like:

  {
   success: 1,
   order: [ list of option ids ]
  }

Parameters:

=over

=item *

id - article id

=item *

option_ids - option ids separated by commas.  These must belong to the
product identified by id.

=back

Permission required: bse_edit_prodopt_move

=cut

sub req_option_reorder {
  my ($self, $req, $article, $articles) = @_;

  $req->check_csrf("admin_move_option")
    or return $self->csrf_error($req, $article, "admin_move_option", "Move Product Option");

  $req->user_can(bse_edit_prodopt_move => $article)
    or return $self->_service_error($req, $article, $articles, "Insufficient product access to move options");

  my @options = $article->db_options;
  my @order = map { split ',' } $req->cgi->param('option_ids');
  my %options = map { $_->{id} => $_ } @options;
  my @new_options;
  for my $id (@order) {
    my $option = delete $options{$id}
      or next;
    push @new_options, $option;
  }
  push @new_options, sort { $a->{display_order} <=> $b->{display_order} } values %options;
  my @display_order = map $_->{display_order}, @options;
  for my $index (0 .. $#new_options) {
    $new_options[$index]{display_order} = $display_order[$index];
    $new_options[$index]->save;
  }

  $req->is_ajax
    and return $req->json_content
      (
	success => 1,
	order => [ map $_->{id}, @new_options ]
      );

  return $self->refresh($article, $req->cgi, undef, "Options reordered");
}

sub _option_value_move {
  my ($self, $req, $article, $articles, $direction) = @_;

  $req->check_csrf("admin_move_option_value")
    or return $self->csrf_error($req, $article, "admin_move_option_value", "Move Product Option Value");

  $req->user_can(bse_edit_prodopt_edit => $article)
    or return $self->_service_error($req, $article, $articles, "Insufficient product access to edit options");

  my %errors;
  my ($option_value, $option) = $self->_get_option_value($req, $article, \%errors);
  keys %errors
    and return $self->_service_error($req, $article, $articles, undef, \%errors);
  my @values = $option->values;
  my ($index) = grep $values[$_]{id} == $option_value->{id}, 0 .. $#values
    or return $self->_service_error($req, $article, $articles, "Unknown option value id");

  $values[$index] = $option_value;

  my $other_index = $index + $direction;
  $other_index >= 0 && $other_index < @values
    or return $self->_service_error($req, $article, $articles, "Can't move option value beyond end");

  my $other = $values[$other_index];

  ($option_value->{display_order}, $other->{display_order}) =
    ($other->{display_order}, $option_value->{display_order});
  $option_value->save;
  $other->save;

  # make sure the json gets the new order
  @values[$index, $other_index] = @values[$other_index, $index];

  $req->is_ajax
    and return $req->json_content
      (
       success => 1,
       order => [ map $_->{id}, @values ]
      );

  return $self->refresh($article, $req->cgi, undef, "Value moved");
}

=item a_option_value_moveup

=item a_option_value_movedown

Move a product option value up/down through the values for a product
option.

On failure perform a service error.

Requires _csrfp for admin_move_option_value

For Ajax requests (or with a _ parameter), returns JSON like:

  {
   success: 1,
   order: [ list of value ids ]
  }

Parameters:

=over

=item *

id - article id

=item *

value_id - option id.  This must belong to the product identified by
id.

=back

Permission required: bse_edit_prodopt_edit

=cut

sub req_option_value_moveup {
  my ($self, $req, $article, $articles) = @_;

  return $self->_option_value_move($req, $article, $articles, -1);
}

sub req_option_value_movedown {
  my ($self, $req, $article, $articles) = @_;

  return $self->_option_value_move($req, $article, $articles, 1);
}

=item a_option_value_reorder

Specify a new order for the values belonging to a product option.

On failure perform a service error.

Requires _csrfp for admin_move_option_value

For Ajax requests (or with a _ parameter), returns JSON like:

  {
   success: 1,
   order: [ list of value ids ]
  }

Parameters:

=over

=item *

id - article id

=item *

option_id - the option to reorder values for

=item *

value_ids - new order for values specified as value ids separated by
commas.

=back

Permission required: bse_edit_prodopt_edit

=cut

sub req_option_value_reorder {
  my ($self, $req, $article, $articles) = @_;

  $req->check_csrf("admin_move_option_value")
    or return $self->csrf_error($req, $article, "admin_move_option_value", "Move Product Option Value");

  $req->user_can(bse_edit_prodopt_edit => $article)
    or return $self->_service_error($req, $article, $articles, "Insufficient product access to edit options");

  my %errors;
  my $option = $self->_get_option($req, $article, \%errors);
  keys %errors
    and return $self->_service_error($req, $article, $articles, undef, \%errors);
  my @order = map { split ',' } $req->cgi->param('value_ids');
  my @values = $option->values;
  my %values = map { $_->{id} => $_ } @values;
  my @new_values;
  for my $id (@order) {
    my $value = delete $values{$id}
      or next;
    push @new_values, $value;
  }
  push @new_values, sort { $a->{display_order} <=> $b->{display_order} } values %values;
  my @display_order = map $_->{display_order}, @values;
  for my $index (0 .. $#new_values) {
    $new_values[$index]{display_order} = $display_order[$index];
    $new_values[$index]->save;
  }

  $req->is_ajax
    and return $req->json_content
      (
	success => 1,
        option => $option->data_only,
	order => [ map $_->{id}, @new_values ]
      );

  return $self->refresh($article, $req->cgi, undef, "Values reordered");
}

sub custom_fields {
  my ($self) = @_;

  my $custom = $self->SUPER::custom_fields();

  require DevHelp::Validate;
  DevHelp::Validate->import;
  return DevHelp::Validate::dh_configure_fields
    (
     $custom,
     $self->cfg,
     PRODUCT_CUSTOM_FIELDS_CFG,
     BSE::DB->single->dbh,
    );
}

sub article_actions {
  my $self = shift;

  return
    (
     $self->SUPER::article_actions,
     a_add_option => 'req_add_option',
     a_confdel_option => 'req_confdel_option',
     a_del_option => 'req_del_option',
     a_edit_option => 'req_edit_option',
     a_save_option => 'req_save_option',
     a_delconf_option => 'req_delconf_option',
     a_delete_option => 'req_delete_option',
     a_get_option => 'req_get_option',
     a_edit_option_value => 'req_edit_option_value',
     a_save_option_value => 'req_save_option_value',
     a_confdel_option_value => 'req_confdel_option_value',
     a_delete_option_value => 'req_delete_option_value',
     a_add_option_value => 'req_add_option_value',
     a_option_value_moveup => 'req_option_value_moveup',
     a_option_value_movedown => 'req_option_value_movedown',
     a_option_value_reorder => 'req_option_value_reorder',
     a_option_moveup => 'req_option_moveup',
     a_option_movedown => 'req_option_movedown',
     a_option_reorder => 'req_option_reorder',
    );
}

1;

=back

=head1 AUTHOR

Tony Cook <tony@develop-help.com>

=cut
