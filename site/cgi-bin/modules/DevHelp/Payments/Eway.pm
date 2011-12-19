package DevHelp::Payments::Eway;
use strict;
use XML::LibXML;
use LWP::UserAgent;
use Carp qw(confess);

our $VERSION = "1.001";

use constant LIVE_URL => "https://www.eway.com.au/gateway_cvn/xmlpayment.asp";
use constant
  TEST_URL => "https://www.eway.com.au/gateway_cvn/xmltest/testpage.asp";

sub new {
  my ($class, $cfg) = @_;

  my $section = "eway payments";
  my $debug = $cfg->entry($section, "debug", 0);
  my $test = $cfg->entry($section, "test");
  defined $test or confess "You must set [$section].test to 1 or 0";

  my $def_url = $test ? TEST_URL : LIVE_URL;
  my $url_key = $test ? "test_url" : "url";
  my $url = $cfg->entry($section, $url_key, $def_url);

  my $merchant_id = $test
    ? $cfg->entry($section, "testmerchantid", "87654321")
    : $cfg->entryErr($section, "merchantid");
  my $timeout = $cfg->entry($section, "timeout", 60);
  my $po_prefix = $cfg->entry($section, "prefix", "");

  if ($debug) {
    print STDERR <<DEBUG;
eWAY configuration:
  Test: $test
  URL: $url
  merchantId: $merchant_id
  timeout: $timeout
  prefix: $po_prefix
DEBUG
  }

  return bless
    {
     test => $test,
     debug => $debug,
     merchant_id => $merchant_id,
     url => $url,
     timeout => $timeout,
     prefix => $po_prefix,
    }, $class;
}

sub payment {
  my ($self, %opts) = @_;

  for my $field (qw(orderno amount cardnumber nameoncard expirydate cvv)) {
    exists $opts{$field} && $opts{$field} =~ /\S/
      or confess "Missing required payment field $field";
  }

  my $orderno = $opts{orderno};
  my $amount = $opts{amount};
  my $card_number = $opts{cardnumber};
  my $name_on_card = $opts{nameoncard};
  my $expiry = $opts{expirydate};
  my $cvv = $opts{cvv};

  if (defined $opts{currency} && $opts{currency} ne 'AUD') {
    return
      {
       success => 0,
       error => 'Unsupported currency',
       statuscode => 5,
      };
  }

  my ($year, $month) = $expiry =~ /^[0-9]{2}([0-9]{2})([0-9]{2})$/
    or confess "Invalid expiry date $expiry\n";

  $amount =~ /^[0-9]+$/
    or confess "Invalid amount $amount\n";

  # eway's requests are simple name => value XML
  my @req =
    (
     ewayCustomerID => $self->{merchant_id},
     ewayTotalAmount => $amount,
     ewayCustomerFirstName => _limit(_first($opts{firstname}, ""), 50),
     ewayCustomerLastName => _limit(_first($opts{lastname}, ""), 50),
     ewayCustomerEmail => _limit(_first($opts{email}, ""), 50),
     ewayCustomerAddress =>
     _limit(join(" ", grep defined, @opts{qw/address1 address2 address3 state suburb countrycode/}), 255),
     ewayCustomerPostcode => _limit(_first($opts{postcode}, ""), 6),
     ewayCustomerInvoiceDescription => _limit(_first($opts{description}, ""), 255),
     ewayCustomerInvoiceRef => $self->{prefix} . $orderno,
     ewayCardHoldersName => _limit($name_on_card, 50),
     ewayCardNumber => $card_number,
     ewayCardExpiryMonth => $month,
     ewayCardExpiryYear => $year,
     ewayTrxnNumber => "",
     ewayOption1 => "",
     ewayOption2 => "",
     ewayOption3 => "",
     ewayCVN => $cvv,
    );

  my $failure;
  my $result = $self->_request(\@req, \$failure)
    or return $failure;

  # sometimes this is:
  #  99,error message
  #  error message
  my $error = $result->{ewayTrxnError};
  my ($code, $message);
  if ($error =~ /^(\d+),(.*)/) {
    $code = 0 + $1;
    $message = $2 || _error_message($1);
  }
  else {
    $code = -1;
    $message = $error;
  }
  if (!exists $result->{ewayTrxnStatus}
      || $result->{ewayTrxnStatus} ne "True") {
    return
      {
       success => 0,
       error => $message,
       statuscode => $code,
      };
  }

  return
    {
     success => 1,
     statuscode => $code,
     error => _error_message($code),
     receipt => $result->{ewayAuthCode},
     transactionid => $result->{ewayTrxnNumber},
    };
}

sub _request {
  my ($self, $req, $rfailure) = @_;

  my $doc = XML::LibXML->createDocument();
  my $root = $doc->createElement("ewaygateway");
  $doc->setDocumentElement($root);
  unless (@$req % 2 == 0) {
    if ($self->{debug}) {
      for my $i (0..$#$req) {
	print STDERR " $i: '$req->[$i]'\n";
      }
    }
    confess "Odd number of request parameters";
  }

  my $cc_num = 'UNKNOWN';
  for (my $i = 0; $i < @$req; $i += 2) {
    my ($key, $value) = ( $req->[$i], $req->[$i+1] );

    if ($key eq "ewayCardNumber") {
      $cc_num = $value;
    }

    my $ele = $doc->createElement($key);
    my $text = $doc->createTextNode($value);
    $ele->appendChild($text);
    $root->appendChild($ele);
  }

  my $req_content = $doc->toString;
  if ($self->{debug}) {
    my $dump = $req_content;
    $dump =~ s/\Q$cc_num/XXX/;

    print STDERR "Request: >>$dump<<\n";
  }

  my $ua = LWP::UserAgent->new;
  my $http_request = HTTP::Request->new(POST => $self->{url});
  $http_request->content($req_content);

  my $response = $ua->request($http_request);
  unless ($response->is_success) {
    if ($self->{debug}) {
      print STDERR "Comms failure: ", $response->status_line, "\n";
    }
    $$rfailure =
      {
       success => 0,
       error => 'Communications error: ' . $response->status_line,
       statuscode => -1,
      };
    return;
  }

  my $parser = XML::LibXML->new;
  my $res_content = $response->decoded_content;

  if ($self->{debug}) {
    print STDERR "Response: >>$res_content<<\n";
  }

  my $rdoc;
  eval {
    $rdoc = $parser->parse_string($res_content);
    1;
  } or do {
    print STDERR "Could not parse response: ", $@, "\n";
    $$rfailure =
      {
       success => 0,
       error => "Parse error: " . $@,
       errorcode => -1,
      };

    return;
  };

  my $res_root = $rdoc->documentElement;
  my %result;
  for my $child ($res_root->childNodes) {
    my $name = $child->nodeName;
    my @kids = $child->childNodes;
    my $value = join '', map { $_->can("data") ? $_->data : "" } @kids;
    $result{$name} = $value;
  }

  return \%result;
}

my %messages =
  (
   0 => "Transaction Approved",
   1 => "Refer to Issuer",
   2 => "Refer to Issuer, special",
   3 => "No Merchant",
   4 => "Pick Up Card",
   5 => "Do Not Honour",
   6 => "Error",
   7 => "Pick Up Card, Special",
   8 => "Honour With Identification",
   9 => "Request In Progress",
   10 => "Approved For Partial Amount",
   11 => "Approved, VIP",
   12 => "Invalid Transaction",
   13 => "Invalid Amount",
   14 => "Invalid Card Number",
   15 => "No Issuer",
   16 => "Approved, Update Track 3",
   19 => "Re-enter Last Transaction",
   21 => "No Action Taken",
   22 => "Suspected Malfunction",
   23 => "Unacceptable Transaction Fee",
   25 => "Unable to Locate Record On File",
   30 => "Format Error",
   31 => "Bank Not Supported By Switch",
   33 => "Expired Card, Capture",
   34 => "Suspected Fraud, Retain Card",
   35 => "Card Acceptor, Contact Acquirer, Retain Card",
   36 => "Restricted Card, Retain Card",
   37 => "Contact Acquirer Security Department, Retain Card",
   38 => "PIN Tries Exceeded, Capture",
   39 => "No Credit Account",
   40 => "Function Not Supported",
   41 => "Lost Card",
   42 => "No Universal Account",
   43 => "Stolen Card",
   44 => "No Investment Account",
   51 => "Insufficient Funds",
   52 => "No Cheque Account",
   53 => "No Savings Account",
   54 => "Expired Card",
   55 => "Incorrect PIN",
   56 => "No Card Record",
   57 => "Function Not Permitted to Cardholder",
   58 => "Function Not Permitted to Terminal",
   59 => "Suspected Fraud",
   60 => "Acceptor Contact Acquirer",
   61 => "Exceeds Withdrawal Limit",
   62 => "Restricted Card",
   63 => "Security Violation",
   64 => "Original Amount Incorrect",
   66 => "Acceptor Contact Acquirer, Security",
   67 => "Capture Card",
   75 => "PIN Tries Exceeded",
   82 => "CVV Validation Error",
   90 => "Cutoff In Progress",
   91 => "Card Issuer Unavailable",
   92 => "Unable To Route Transaction",
   93 => "Cannot Complete, Violation Of The Law",
   94 => "Duplicate Transaction",
   96 => "System Error",
  );

sub _error_message {
  my ($code) = @_;

  return $messages{$code+0} || "Unknown error $code";
}

sub _first {
  for my $value (@_) {
    defined $value and return $value;
  }

  return;
}

sub _limit {
  my ($value, $limit) = @_;

  $value =~ s/\s+/ /g;
  length $value <= $limit
    and return $value;

  substr($value, $limit) = "";

  if ($limit > 20) {
    $value =~ s/ \S{1,5}$//;
  }

  return $value;
}

1;

=head1 NAME

  DevHelp::Payments::Eway - card payment driver for eway.com.au

=head1 SYNOPSIS

  [shop]
  cardprocessor=DevHelp::Payments::Eway

  [eway payments]
  ; test mode
  test=1
  ; test_url=https://www.eway.com.au/gateway_cvn/xmltest/testpage.asp
  ; test_merchantid=87654321

  ; production mode
  test=0
  merchantid=...
  ; url=https://www.eway.com.au/gateway_cvn/xmlpayment.asp

  ; common:
  prefix=
  timeout=60

=head1 DESCRIPTION

This is a credit card processing driver for BSE that works with
eway.com.au.

=head1 CONFIGURATION

The following parameters can be set in the C<[eway payments]> section:

=over

=item test

If non-zero test transactions are performed, using the test
configuration.  If test is zero live transactions are performed.
C<test> must be set.

=item merchantid

The merchant id supplied by eway, used for live transactions.
Required for live processing.

=item testmerchantid

The merchant id used for test transactions.  Defaults to 87654321.

=item prefix

The prefix used on order numbers supplied to eway.

=item url

The eway url for live transactions.  Default:
https://www.eway.com.au/gateway_cvn/xmlpayment.asp

=item test_url

The eway url for test transctions.  Default:
https://www.eway.com.au/gateway_cvn/xmltest/testpage.asp

=item timeout

The timeout for requests made to eway in sections.  Default: 60.

=item debug

If non-zero then debugging information is sent to STDERR.  Default: 0

=back

=head1 AUTHOR

Tony Cook <tony@develop-help.com>

=head1 LICENSE

The same terms as perl itself.

=cut
