package BSE::PayPal;
use strict;
use BSE::Cfg;
use BSE::Util::HTML;
use BSE::Shop::Util qw(:payment);
use Carp qw(confess);

our $VERSION = "1.000";

use constant DEF_TEST_WS_URL => "https://api-3t.sandbox.paypal.com/nvp";
use constant DEF_TEST_REFRESH_URL => "https://www.sandbox.paypal.com/webscr";

use constant DEF_LIVE_WS_URL => "https://api-3t.paypal.com/nvp";
use constant DEF_LIVE_REFRESH_URL => "https://www.paypal.com/cgibin/webscr";

my %defs =
  (
   test_ws_url => DEF_TEST_WS_URL,
   test_refresh_url => DEF_TEST_REFRESH_URL,

   live_ws_url => DEF_LIVE_WS_URL,
   live_refresh_url => DEF_LIVE_REFRESH_URL,
  );

sub _test {
  my ($cfg) = @_;

  return $cfg->entry("paypal", "test", 1);
}

sub _cfg {
  my ($cfg, $key) = @_;

  my $realkey = _test($cfg) ? "test_$key" : "live_$key";
  if (exists $defs{$realkey}) {
    return $cfg->entry("paypal", $realkey, $defs{$realkey});
  }
  else {
    return $cfg->entryErr("paypal", $realkey);
  }
}

sub _base_ws_url {
  my ($cfg) = @_;

  return _cfg($cfg, "ws_url");
}

sub _base_refresh_url {
  my ($cfg) = @_;

  return _cfg($cfg, "refresh_url");
}

sub _api_signature {
  my ($cfg) = @_;

  return _cfg($cfg, "api_signature");
}

sub _api_username {
  my ($cfg) = @_;

  return _cfg($cfg, "api_username");
}

sub _api_password {
  my ($cfg) = @_;

  return _cfg($cfg, "api_password");
}

sub _format_amt {
  my ($price) = @_;

  return sprintf("%d.%02d", int($price / 100), $price % 100);
}

sub _order_amt {
  my ($order) = @_;

  return _format_amt($order->total);
}

sub _order_currency {
  my ($order) = @_;

  return BSE::Cfg->single->entry("shop", "currency_code", "AUD")
}

sub payment_url {
  my ($class, %opts) = @_;

  my $order = delete $opts{order}
    or confess "Missing order";
  my $rmsg = delete $opts{msg}
    or confess "Missing msg";
  my $who = delete $opts{user} || "U";
  my $cfg = BSE::Cfg->single;

  my %info = _set_express_checkout($cfg, $order, $who, $rmsg)
    or return;

  $order->set_paypal_token($info{TOKEN});
  $order->save;

  my $url = _make_url(_base_refresh_url($cfg),
		      {
		       cmd => "_express-checkout",
		       token => $info{TOKEN},
		       useraction => "confirm",
		       AMT => _order_amt($order),
		       CURRENCYCODE => _order_currency($order)
		      }
		     );

#   BSE::TB::AuditLog->log
#       (
#        component => "shop:paypal:paymenturl",
#        level => "debug",
#        object => $order,
#        actor => $who,
#        msg => "URL $url",
#       );

  return $url;
}

# the _api_*() functions will die if not configured
sub configured {
  my $cfg = BSE::Cfg->single;

  return eval
    {
      _api_username($cfg) && _api_password($cfg) && _api_signature($cfg);
      1;
    };
}

sub pay_order {
  my ($class, %opts) = @_;

  my $order = delete $opts{order}
    or confess "Missing order";
  my $req = delete $opts{req}
    or confess "Missing req";
  my $rmsg = delete $opts{msg}
    or confess "Missing msg";

  my $cgi = $req->cgi;
  my $cfg = $req->cfg;
  my $token = $cgi->param("token");
  unless ($token) {
    $$rmsg = $req->catmsg("msg:bse/shop/paypal/notoken");
    return;
  }
  my $payerid = $cgi->param("PayerID");
  unless ($payerid) {
    $$rmsg = $req->catmsg("msg:bse/shop/paypal/nopayerid");
    return;
  }
  unless ($token eq $order->paypal_token) {
    print STDERR "cgi $token order ", $order->paypal_token, "\n";
    $$rmsg = $req->catmsg("msg:bse/shop/paypal/badtoken");
    return;
  }

  my %info;
  $DB::single = 1;
  if (_do_express_checkout_payment
      ($cfg, $rmsg, $order, scalar($req->siteuser), $token, $payerid, \%info)) {
    $order->set_paypal_tran_id($info{TRANSACTIONID});

  }
  elsif (keys %info) {
    unless ($info{L_ERRORCODE}
	    && $info{L_ERRORCODE} == 10415
	    && $info{CHECKOUTSTATUS}
	    && $info{CHECKOUTSTATUS} eq "PaymentActionCompleted"
	    && $info{PAYMENTREQUEST_0_TRANSACTIONID}) {
      return; # something else went wrong
    }

    # already processed, maybe there was an error when the user first
    # returned, treat it as completed
    $order->set_paypal_tran_id($info{PAYMENTREQUEST_0_TRANSACTIONID});
  }
  $order->set_paypal_token("");
  $order->set_paidFor(1);
  $order->set_paymentType(PAYMENT_PAYPAL);
  $order->set_complete(1);
  $order->save;
  BSE::TB::AuditLog->log
      (
       component => "shop:paypal:pay",
       level => "notice",
       object => $order,
       actor => scalar($req->siteuser) || "U",
       msg => "Order paid via Paypal, transaction ".$order->paypal_tran_id,
      );

  return 1;
}

sub refund_order {
  my ($class, %opts) = @_;

  my $order = delete $opts{order}
    or confess "Missing order";
  my $rmsg = delete $opts{msg}
    or confess "Missing msg";
  my $req = delete $opts{req}
    or confess "Missing req";

  unless ($order->paymentType eq PAYMENT_PAYPAL) {
    $$rmsg = "This order was not paid by paypal";
    return;
  }

  my $cfg = BSE::Cfg->single;
  my %info = _do_refund_transaction($cfg, $rmsg, $order, scalar($req->user))
    or return;

  $order->set_paidFor(0);
  $order->save;

  BSE::TB::AuditLog->log
      (
       component => "shop:paypal:refund",
       level => "notice",
       object => $order,
       actor => scalar($req->user) || "U",
       msg => "PayPal payment refunded, transaction $info{REFUNDTRANSACTIONID}",
      );

  return 1;
}

sub _do_refund_transaction {
  my ($cfg, $rmsg, $order, $who) = @_;

  my %params =
    (
     VERSION => "62.0",
     TRANSACTIONID => $order->paypal_tran_id,
     REFUNDTYPE => "Full",
    );

  my %info = _api_req($cfg, $rmsg, $order, $who, "RefundTransaction", \%params)
    or return;

  return %info;
}

sub _make_qparam {
  my ($param) = @_;

  return join("&", map { "$_=".escape_uri($param->{$_}) } sort keys %$param);
}

sub _make_url {
  my ($base, $param) = @_;

  my $sep = $base =~ /\?/ ? "&" : "?";

  return $base . $sep . _make_qparam($param);
}

sub _shop_url {
  my ($cfg, $action, @params) = @_;

  return $cfg->user_url("shop", $action, @params);
}

sub _populate_from_order {
  my ($params, $order, $cfg) = @_;

  $params->{AMT} = _order_amt($order);
  $params->{CURRENCYCODE} = _order_currency($order);

  my $index = 0;
  for my $item ($order->items) {
    $params->{"L_NAME$index"} = $item->title;
    $params->{"L_AMT$index"} = _format_amt($item->price);
    $params->{"L_QTY$index"} = $item->units;
    $params->{"L_NUMBER$index"} = $item->product_code
      if $item->product_code;
    ++$index;
  }
  $params->{SHIPPINGAMT} = _format_amt($order->shipping_cost)
    if $order->shipping_cost;

  # use our shipping information
  my $country_code = $order->deliv_country_code;
  if ($country_code && $cfg->entry("paypal", "shipping", 1)) {
    $params->{SHIPTONAME} = $order->delivFirstName . " " . $order->delivLastName;
    $params->{SHIPTOSTREET} = $order->delivStreet;
    $params->{SHIPTOSTREET2} = $order->delivStreet2;
    $params->{SHIPTOCITY} = $order->delivSuburb;
    $params->{SHIPTOSTATE} = $order->delivState;
    $params->{SHIPTOZIP} = $order->delivPostCode;
    $params->{SHIPTOCOUNTRYCODE} = $country_code;
    $params->{ADDROVERRIDE} = 1;
  }
  else {
    $params->{NOSHIPPING} = 1;
  }
}

sub _set_express_checkout {
  my ($cfg, $order, $who, $rmsg) = @_;

  my %params =
    (
     $cfg->entriesCS("paypal custom"),
     VERSION => "62.0",
     RETURNURL => _shop_url($cfg, "paypalret", order => $order->randomId),
     CANCELURL => _shop_url($cfg, "paypalcan", order => $order->randomId),
     PAYMENTACTION => "Sale",
    );

  _populate_from_order(\%params, $order, $cfg);

  my %info = _api_req($cfg, $rmsg, $order, $who,"SetExpressCheckout",
		      \%params)
    or return;

  unless ($info{TOKEN}) {
    $$rmsg = "No token returned by PayPal";
    return;
  }

  return %info;
}

 sub _get_express_checkout_details {
   my ($cfg, $order, $who, $rmsg, $token) = @_;

   my %params =
     (
      TOKEN => $token,
      VERSION => "62.0",
     );

   my %info = _api_req($cfg, $rmsg, $order, $who, "GetExpressCheckoutDetails",
 		      \%params)
     or return;

   return %info;
}

sub _do_express_checkout_payment {
  my ($cfg, $rmsg, $order, $who, $token, $payerid, $info) = @_;

  my %params =
    (
     VERSION => "62.0",
     PAYMENTACTION => "Sale",
     TOKEN => $token,
     PAYERID => $payerid,
    );

  _populate_from_order(\%params, $order, $cfg);

  my %info = _api_req($cfg, $rmsg, $order, $who || "U", "DoExpressCheckoutPayment",
		      \%params, $info)
    or return;

  return %info;
}

# Low level API request
sub _api_req {
  my ($cfg, $rmsg, $order, $who, $method, $param, $info) = @_;

  $who ||= "U";

  require LWP::UserAgent;
  my $ua = LWP::UserAgent->new;
  $param->{METHOD} = $method;
  $param->{USER} = _api_username($cfg);
  $param->{PWD} = _api_password($cfg);
  $param->{SIGNATURE} = _api_signature($cfg);

  my $post = _make_qparam($param);

  my $req = HTTP::Request->new(POST => _base_ws_url($cfg));
  $req->content($post);

  my $result = $ua->request($req);

  require BSE::TB::AuditLog;
  BSE::TB::AuditLog->log
      (
       component => "shop:paypal",
       function => $method,
       level => "info",
       object => $order,
       actor => $who,
       msg => "PayPal $method request",
       dump => "Request:<<\n" . $req->as_string . "\n>>\n\nResult:<<\n" . $result->as_string . "\n>>",
      );

  my %info;
  for my $entry (split /&/, $result->decoded_content) {
    my ($key, $value) = split /=/, $entry, 2;
    $info{$key} = unescape_uri($value);
  }

  %$info = %info if $info;
  unless ($info{ACK} =~ /^Success/) {
    BSE::TB::AuditLog->log
	(
	 component => "shop:paypal",
	 function => $method,
	 level => "crit",
	 object => $order,
	 actor => $who,
	 msg => "PayPal $method failure",
	 dump => $result->as_string,
	);
    $$rmsg = $info{L_LONGMESSAGE0};
    return;
  }

  return %info;
}

1;
