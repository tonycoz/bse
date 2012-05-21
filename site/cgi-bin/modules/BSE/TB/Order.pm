package BSE::TB::Order;
use strict;
# represents an order from the database
use Squirrel::Row;
use vars qw/@ISA/;
@ISA = qw/Squirrel::Row/;
use Carp 'confess';
use BSE::Shop::PaymentTypes;

our $VERSION = "1.016";

sub columns {
  return qw/id
           delivFirstName delivLastName delivStreet delivSuburb delivState
	   delivPostCode delivCountry
           billFirstName billLastName billStreet billSuburb billState
           billPostCode billCountry
           telephone facsimile emailAddress
           total wholesaleTotal gst orderDate
           ccNumberHash ccName ccExpiryHash ccType
           filled whenFilled whoFilled paidFor paymentReceipt
           randomId cancelled userId paymentType
           customInt1 customInt2 customInt3 customInt4 customInt5
           customStr1 customStr2 customStr3 customStr4 customStr5
           instructions billTelephone billFacsimile billEmail
           siteuser_id affiliate_code shipping_cost
           delivMobile billMobile
           ccOnline ccSuccess ccReceipt ccStatus ccStatusText
           ccStatus2 ccTranId complete delivOrganization billOrganization
           delivStreet2 billStreet2 purchase_order shipping_method
           shipping_name shipping_trace
	   paypal_token paypal_tran_id freight_tracking stage ccPAN
	   paid_manually/;
}

sub table {
  return "orders";
}

sub defaults {
  require BSE::Util::SQL;
  require Digest::MD5;
  return
    (
     billFirstName => "",
     billLastName => "",
     billStreet => "",
     billSuburb => "",
     billState => "",
     billPostCode => "",
     billCountry => "",
     total => 0,
     wholesaleTotal => 0,
     gst => 0,
     orderDate => BSE::Util::SQL::now_datetime(),
     filled => 0,
     whenFilled => undef,
     whoFilled => '',
     paidFor => 0,
     paymentReceipt => '',
     randomId => Digest::MD5::md5_hex(time().rand().{}.$$),
     ccNumberHash => '',
     ccName => '',
     ccExpiryHash => '',
     ccType => '',
     randomId => '',
     cancelled => 0,
     userId => '',
     paymentType => 0,
     customInt1 => undef,
     customInt2 => undef,
     customInt3 => undef,
     customInt4 => undef,
     customInt5 => undef,
     customStr1 => undef,
     customStr2 => undef,
     customStr3 => undef,
     customStr4 => undef,
     customStr5 => undef,
     instructions => '',
     siteuser_id => undef,
     affiliate_code => '',
     shipping_cost => 0,
     ccOnline => 0,
     ccSuccess => 0,
     ccReceipt => '',
     ccStatus => 0,
     ccStatusText => '',
     ccStatus2 => '',
     ccTranId => '',
     complete => 0,
     purchase_order => '',
     shipping_method => '',
     shipping_name => '',
     shipping_trace => undef,
     paypal_token => "",
     paypal_tran_id => "",
     freight_tracking => "",
     stage => "incomplete",
     ccPAN => "",
     paid_manually => 0,
    );
}

sub address_columns {
  return qw/
           delivFirstName delivLastName delivStreet delivSuburb delivState
	   delivPostCode delivCountry
           billFirstName billLastName billStreet billSuburb billState
           billPostCode billCountry
           telephone facsimile emailAddress
           instructions billTelephone billFacsimile billEmail
           delivMobile billMobile
           delivOrganization billOrganization
           delivStreet2 billStreet2/;
}

sub user_columns {
  return qw/userId siteuser_id/;
}

sub payment_columns {
  return qw/ccNumberHash ccName ccExpiryHash ccType
           paidFor paymentReceipt paymentType
           ccOnline ccSuccess ccReceipt ccStatus ccStatusText
           ccStatus2 ccTranId ccPAN paid_manually/;
}

=item billing_to_delivery_map

Return a hashref where the key is a billing field and the value is the
corresponding delivery field.

=cut

{
  my %billing_to_delivery =
    (
     billEmail => "emailAddress",
     billFirstName => "delivFirstName",
     billLastName => "delivLastName",
     billStreet => "delivStreet",
     billStreet2 => "delivStreet2",
     billSuburb => "delivSuburb",
     billState => "delivState",
     billPostCode => "delivPostCode",
     billCountry => "delivCountry",
     billTelephone => "telephone",
     billMobile => "delivMobile",
     billFacsimile => "facsimile",
     billOrganization => "delivOrganization",
    );

  sub billing_to_delivery_map {
    return \%billing_to_delivery;
  }
}

=item siteuser

returns the SiteUser object of the user who made this order.

=cut

sub siteuser {
  my ($self) = @_;

  if ($self->siteuser_id) {
    require SiteUsers;
    my $user = SiteUsers->getByPkey($self->siteuser_id);
    $user and return $user;
  }

  $self->{userId} or return;

  require SiteUsers;

  return ( SiteUsers->getBy(userId=>$self->{userId}) )[0];
}

sub items {
  my ($self) = @_;

  require BSE::TB::OrderItems;
  return BSE::TB::OrderItems->getBy(orderId => $self->{id});
}

sub files {
  my ($self) = @_;

  require BSE::TB::ArticleFiles;
  return BSE::TB::ArticleFiles->getSpecial(orderFiles=>$self->{id});
}

sub paid_files {
  my ($self) = @_;

  $self->paidFor
    or return;

  require BSE::TB::ArticleFiles;
  return BSE::TB::ArticleFiles->getSpecial(orderPaidFor => $self->id);
}

sub products {
  my ($self) = @_;

  require Products;
  Products->getSpecial(orderProducts=>$self->{id});
}

sub valid_fields {
  my ($class, $cfg) = @_;

  my %fields =
    (
     delivFirstName => { description=>'Delivery First Name',
			 rules=>'dh_one_line' },
     delivLastName => { description => 'Delivery Last Name',
			 rules=>'dh_one_line'  },
     delivOrganization => { description => 'Delivery Organization',
			    rules=>'dh_one_line'  },
     delivStreet => { description => 'Delivery Street',
			 rules=>'dh_one_line'  },
     delivStreet2 => { description => 'Delivery Street 2',
			 rules=>'dh_one_line'  },
     delivState => { description => 'Delivery State',
			 rules=>'dh_one_line'  },
     delivSuburb => { description => 'Delivery Suburb',
			 rules=>'dh_one_line'  },
     delivPostCode => { description => 'Delivery Post Code',
			 rules=>'dh_one_line;dh_int_postcode'  },
     delivCountry => { description => 'Delivery Country',
			 rules=>'dh_one_line'  },
     billFirstName => { description => 'Billing First Name',
			 rules=>'dh_one_line'  },
     billLastName => { description => 'Billing Last Name',
			 rules=>'dh_one_line'  },
     billOrganization => { description => 'Billing Organization',
			   rules=>'dh_one_line'  },
     billStreet => { description => 'Billing Street',
			 rules=>'dh_one_line'  },
     billStreet2 => { description => 'Billing Street 2',
			 rules=>'dh_one_line'  },
     billSuburb => { description => 'Billing Suburb',
			 rules=>'dh_one_line'  },
     billState => { description => 'Billing State',
			 rules=>'dh_one_line'  },
     billPostCode => { description => 'Billing Post Code',
			 rules=>'dh_one_line;dh_int_postcode'  },
     billCountry => { description => 'Billing First Name',
			 rules=>'dh_one_line'  },
     telephone => { description => 'Telephone Number',
		    rules => "phone" },
     facsimile => { description => 'Facsimile Number',
		    rules => 'phone' },
     emailAddress => { description => 'Email Address',
		       rules=>'email' },
     instructions => { description => 'Instructions' },
     billTelephone => { description => 'Billing Telephone Number',
			rules=>'phone' },
     billFacsimile => { description => 'Billing Facsimile Number',
			rules=>'phone' },
     billEmail => { description => 'Billing Email Address',
		    rules => 'email;required' },
     delivMobile => { description => 'Delivery Mobile Number',
		      rules => 'phone' },
     billMobile => { description => 'Billing Mobile Number',
		     rules=>'phone' },
     instructions => { description => 'Instructions' },
     purchase_order => { description => 'Purchase Order No' },
     shipping_cost => { description => 'Shipping charges' },
     shipping_method => { description => 'Shipping method' },
    );

  for my $field (keys %fields) {
    my $display = $cfg->entry('shop', "display_$field");
    $display and $fields{$field}{description} = $display;
  }

  return %fields;
}

sub valid_rules {
  my ($class, $cfg) = @_;

  return;
}

sub valid_payment_fields {
  my ($class, $cfg) = @_;

  my %fields =
    (
     cardNumber =>
     {
      description => "Credit Card Number",
      rules=>"creditcardnumber",
     },
     cardExpiry =>
     {
      description => "Credit Card Expiry Date",
      rules => 'creditcardexpirysingle',
     },
     ccName => { description => "Credit Card Holder" },
     ccType => { description => "Credit Card Type" },
     cardVerify =>
     {
      description => 'Card Verification Value',
      rules => 'creditcardcvv',
     },
    );

  for my $field (keys %fields) {
    my $display = $cfg->entry('shop', "display_$field");
    $display and $fields{$field}{description} = $display;
  }

  return %fields;
}

sub valid_payment_rules {
  return;
}

sub clear_items {
  my ($self) = @_;

  confess "Attempt to clear items on completed order $self->{id}"
    if $self->{complete};

  BSE::DB->run(deleteOrdersItems => $self->{id});
}

sub add_item {
  my ($self, %opts) = @_;

  my $prod = delete $opts{product}
    or confess "Missing product option";
  my $units = delete $opts{units} || 1;

  my $options = '';
  my @dboptions;
  if ($opts{options}) {
    if (ref $opts{options}) {
      @dboptions = @{delete $opts{options}};
    }
    else {
      $options = delete $opts{options};
    }
  }

  require BSE::TB::OrderItems;
  my %item =
    (
     productId => $prod->id,
     orderId => $self->id,
     units => $units,
     price => $prod->retailPrice,
     options => $options,
     max_lapsed => 0,
     session_id => 0,
     ( map { $_ => $prod->{$_} }
       qw/wholesalePrice gst customInt1 customInt2 customInt3 customStr1 customStr2 customStr3 title description subscription_id subscription_period product_code/
     ),
    );

  $self->set_total($self->total + $prod->retailPrice * $units);

  return BSE::TB::OrderItems->make(%item);
}

sub deliv_country_code {
  my ($self) = @_;

  my $use_codes = BSE::Cfg->single->entry("shop", "country_code", 0);
  if ($use_codes) {
    return $self->delivCountry;
  }
  else {
    require BSE::Countries;
    return BSE::Countries::bse_country_code($self->delivCountry);
  }
}

=item stage

Return the order stage.

If the stage is empty, guess from the order flags.

=cut

sub stage {
  my ($self) = @_;

  if ($self->{stage} ne "") {
    return $self->{stage};
  }

  if (!$self->complete) {
    return "incomplete";
  }
  elsif ($self->filled) {
    return "shipped";
  }
  else {
    return "unprocessed";
  }
}

sub stage_description {
  my ($self, $lang) = @_;

  return BSE::TB::Orders->stage_label($self->stage, $lang);
}

sub stage_description_id {
  my ($self) = @_;

  return BSE::TB::Orders->stage_label_id($self->stage);
}

=item delivery_mail_recipient

Return a value suitable for BSE::ComposeMail's to parameter for the
shipping email address.

=cut

sub delivery_mail_recipient {
  my ($self) = @_;

  my $user = $self->siteuser;
  my $email = $self->emailAddress || $self->billEmail;

  if ($user && $user->email eq $email) {
    return $user;
  }

  return $email;
}

=item _tags

Internal method with the common code between tags() and mail_tags().

=cut

sub _tags {
  my ($self, $escape) = @_;

  require BSE::Util::Tags;
  require BSE::TB::OrderItems;
  require BSE::Util::Iterate;
  my $it;
  my $art;
  my $esc;
  my $obj;
  if ($escape) {
    require BSE::Util::HTML;
    $it = BSE::Util::Iterate::Objects->new;
    $art = \&BSE::Util::Tags::tag_article;
    $obj = \&BSE::Util::Tags::tag_object;
    $esc = \&BSE::Util::HTML::escape_html;
  }
  else {
    $it = BSE::Util::Iterate::Objects::Text->new;
    $art = \&BSE::Util::Tags::tag_article_plain;
    $obj = \&BSE::Util::Tags::tag_object_plain;
    $esc = sub { return $_[0] };
  }

  my $cfg = BSE::Cfg->single;
  my $must_be_paid = $cfg->entryBool('downloads', 'must_be_paid', 0);
  my $must_be_filled = $cfg->entryBool('downloads', 'must_be_filled', 0);

  my %item_cols = map { $_ => 1 } BSE::TB::OrderItem->columns;
  my %products;
  my $current_item;
  my $current_file;
  return
    (
     order => [ $obj, $self ],
     $it->make
     (
      single => "item",
      plural => "items",
      code => [ items => $self ],
      store => \$current_item,
     ),
     extended => sub {
       my ($args) = @_;

       $current_item
	 or return '* only usable in items iterator *';

       $item_cols{$args}
	 or return "* unknown item column $args *";

       return $current_item->$args() * $current_item->units;
     },
     $it->make
     (
      single => "option",
      plural => "options",
      code => sub {
	$current_item
	  or return;
	return $current_item->option_hashes
      },
      nocache => 1,
     ),
     options => sub {
       $current_item
	 or return '* only in the items iterator *';
       return $esc->($current_item->nice_options);
     },
     product => sub {
       $current_item
	 or return '* only usable in items *';

       require Products;
       my $id = $current_item->productId;
       $products{$id} ||= Products->getByPkey($id);

       my $product = $products{$id}
	 or return '';

       return $art->($product, $cfg, $_[0]);
     },
     $it->make
     (
      single => 'orderfile',
      plural => 'orderfiles',
      code => [ files => $self ],
      store => \$current_file,
     ),
     $it->make
     (
      single => "prodfile",
      plural => "prodfiles",
      code => sub {
       $current_item
	 or return '* only usable in items *';

       require Products;
       my $id = $current_item->productId;
       $products{$id} ||= Products->getByPkey($id);

       my $product = $products{$id}
	 or return '';

       return $product->files;
      },
      store => \$current_file,
     ),
     ifFileAvail => sub {
       $current_file or return 0;
       $current_file->{forSale} or return 1;

       return 0 if $must_be_paid && !$self->{paidFor};
       return 0 if $must_be_filled && !$self->{filled};

       return 1;
     },
    );
}

=item mail_tags

=cut

sub mail_tags {
  my ($self) = @_;

  return $self->_tags(0);
}

=item tags

Return template tags suitable for an order (non-mail)

=cut

sub tags {
  my ($self) = @_;

  return $self->_tags(1);
}

sub send_shipped_email {
  my ($self) = @_;

  my $to = $self->delivery_mail_recipient;
  require BSE::ComposeMail;
  my $mailer = BSE::ComposeMail->new(cfg => BSE::Cfg->single);
  require BSE::Util::Tags;
  my %acts =
    (
     BSE::Util::Tags->mail_tags(),
     $self->mail_tags,
    );
  my %opts =
    (
     to => $to,
     subject => "Your order has shipped",
     template => "email/ordershipped",
     acts => \%acts,
     log_msg => "Notify customer order has shipped",
     log_object => $self,
     log_component => "shopadmin:orders:saveorder",
    );
  if ($self->emailAddress && $self->billEmail
      && lc $self->emailAddress ne $self->billEmail) {
    $opts{cc} = $self->billEmail;
  }

  $mailer->send(%opts);
}

sub new_stage {
  my ($self, $who, $stage, $stage_note) = @_;

  unless ($stage ne $self->stage
	  || defined $stage_note && $stage_note =~ /\S/) {
    return;
  }

  my $old_stage = $self->stage;
  my $msg = "Set to stage '$stage'";
  if (defined $stage_note && $stage_note =~ /\S/) {
    $msg .= ": $stage_note";
  }
  require BSE::TB::AuditLog;
  BSE::TB::AuditLog->log
    (
     component => "shopadmin:orders:saveorder",
     object => $self,
     msg => $msg,
     level => "info",
     actor => $who || "U"
    );

  if ($stage ne $old_stage) {
    $self->set_stage($stage);
    if ($stage eq "shipped") {
      if (!$self->filled) {
	require BSE::Util::SQL;

	$self->set_whoFilled($who ? $who->logon : "-unknown-");
	$self->set_whenFilled(BSE::Util::SQL::now_datetime());
      }
      $self->send_shipped_email();
      $self->set_filled(1);
    }
    else {
      $self->set_filled(0);
    }
  }
}

sub set_ccPANTruncate {
  my ($self, $pan) = @_;

  if (length $pan > 4) {
    $pan = substr($pan, -4);
  }

  $self->set_ccPAN($pan);
}

=item is_manually_paid

Returns true if the order is marked as manually paid, either through
the older PAYMENT_MANUAL paymentType value or via the newer flag.

=cut

sub is_manually_paid {
  my ($self) = @_;

  return $self->paidFor &&
    ($self->paid_manually || $self->paymentType == PAYMENT_MANUAL);
}

1;
