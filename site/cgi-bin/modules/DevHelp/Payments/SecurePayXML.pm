package DevHelp::Payments::SecurePayXML;
use strict;
use Carp 'confess';
use Digest::MD5 qw(md5_hex);
use POSIX qw(strftime);
use LWP::UserAgent;
use XML::Simple;

my $sequence = 0;

sub new {
  my ($class, $cfg) = @_;

  my $debug = $cfg->entry('securepay xml', 'debug', 0);

  my $test = $cfg->entry('securepay xml', 'test', 1);
  my $livemerchantid = $cfg->entry('securepay xml', 'merchantid');
  my $testmerchantid = $cfg->entry('securepay xml', 'testmerchantid');
  my $testurl =  $cfg->entry('securepay xml', 'testurl', 
			     "https://www.securepay.com.au/test/payment");
  my $liveurl =  $cfg->entry('securepay xml', 'url',
			     "https://www.securepay.com.au/xmlapi/payment");
  my $timeout = $cfg->entry('securepay xml', 'timeout');
  my $testpassword = $cfg->entry('securepay xml', 'testpassword');
  my $livepassword = $cfg->entry('securepay xml', 'password');
  my $poprefix = $cfg->entry('securepay xml', 'prefix', '');
  if ($debug) {
    print STDERR "SecurePay XML Config:\n",
      "  test: $test\n  url: $testurl - $liveurl\n  merchantid: $testmerchantid - $livemerchantid\n  timeout:",
	defined($timeout) ? $timeout : "undef", "\n  prefix: $poprefix\n";
       
  }
  my $result_code = $cfg->entry('securepay xml', 'result_code');
  return bless {
		test => $test,
		livemerchantid => $livemerchantid,
		testmerchantid => $testmerchantid,
		liveurl => $liveurl,
		testurl => $testurl,
		timeout => $timeout,
		testpassword => $testpassword,
		livepassword => $livepassword,
		prefix => $poprefix,
		debug => $debug,
		result_code => $result_code,
		paranoid => $cfg->entry('securepay xml', 'paranoid', 1),
	       }, $class;
}

my $payment_template = <<'XML';
<?xml version="1.0" encoding="UTF-8"?>
<SecurePayMessage>
  <MessageInfo>
    <messageID><:messageid:></messageID>
    <messageTimestamp><:timestamp:></messageTimestamp>
    <timeoutValue><:timeout:></timeoutValue>
    <apiVersion>xml-4.2</apiVersion>
  </MessageInfo>
  <MerchantInfo>
    <merchantID><:merchantid:></merchantID>
    <password><:password:></password>
  </MerchantInfo>
  <RequestType>Payment</RequestType>
  <Payment>
    <TxnList count="1">
      <Txn ID="1">
        <txnType>0</txnType>
        <txnSource>23</txnSource>
        <amount><:amount:></amount>
        <purchaseOrderNo><:orderno:></purchaseOrderNo>
        <CreditCardInfo>
          <cardNumber><:cardnumber:></cardNumber>
          <expiryDate><:expirydate:></expiryDate>
<:cvvtag:>
        </CreditCardInfo>
      </Txn>
    </TxnList>
  </Payment>
</SecurePayMessage>
XML

sub payment {
  my ($self, %args) = @_;

  my $debug = $self->{debug};

  for my $name (qw/orderno amount cardnumber expirydate/) {
    defined $args{$name}
      or confess "Missing $name argument";
  }

  if (defined $args{currency} && $args{currency} ne 'AUD') {
    return
      {
       success => 0,
       error => 'Unsupported currency',
       statuscode => 5,
      };
  }

  my $orderno = $self->{prefix} . $args{orderno};

  my $amount = $args{amount};
  if ($self->{test} && defined($self->{result_code})) {
    $amount = 100 * int($amount / 100) + $self->{result_code};
  }

  if ($args{expirydate} =~ /^(\d\d\d\d)(\d\d)$/) {
    $args{expirydate} = sprintf("%02d/%02d", $2, $1 %100);
  }

  # get timezone and convert to minutes
  my $tz_hour_min = strftime("%z", localtime);
  my $tz_offset;
  if (my ($tz_sign, $tz_hours, $tz_min) = 
      $tz_hour_min =~ /^([+-])(\d\d)(\d\d)$/) {
    my $min = $tz_hours * 60 + $tz_min;
    $tz_offset = $tz_sign . sprintf("%03d", $min);
  }
  else {
    print STDERR "Could not parse $tz_hour_min for timezone offset, assuming zero\n" 
      if $debug;
    $tz_offset = '+000';
  }

  # md5_hex returns a 32 char str, max is meant to be 30
  my $message_id = md5_hex(++$sequence . $orderno . time(), $$);
  substr($message_id, 30) = '';

  # yet another templating system, if we ever need something more
  # sophisticated than this here switch to Squirrel::Template
  my %replace =
    (
     expirydate => $args{expirydate},
     amount => $amount,
     orderno => $orderno,
     cardnumber => $args{cardnumber},
     messageid => $message_id,
     timestamp => strftime("%Y%d%m%H%M%S000000", localtime) . $tz_offset,
     timeout => $self->{timeout} || 60,
     currency => $args{currency} || 'AUD',
     cvvtag => '',
    );
  
  my $url;
  if ($self->{test}) {
    $replace{merchantid} = $self->{testmerchantid};
    $replace{password} = $self->{testpassword};
    $url = $self->{testurl};
  }
  else {
    $replace{merchantid} = $self->{livemerchantid};
    $replace{password} = $self->{livepassword};
    $url = $self->{liveurl};
  }

  # XML escape all of these
  for my $value (values %replace) {
    $value =~ s/([<>&])/"&#".ord($1).";"/ge;
  }

  # but not these
  if ($args{cvv}) {
    $replace{cvvtag} = "<cvv>$args{cvv}</cvv>";
  }

  my $xml = $payment_template;
  eval {
    $xml =~ s/<:(\w+):>/exists $replace{$1} ? $replace{$1} : die "Key $1 not found" /ge;
  };
  if ($@) {
    return
      {
       success => 0,
       error => 'Internal error: '. $@,
       statuscode => -1,
      };
  }

  my $ua = LWP::UserAgent->new;
  my $http_request = HTTP::Request->new(POST => $url);

  $http_request->content($xml);
  my $response = $ua->request($http_request);
  unless ($response->is_success) {
    return
      {
       success => 0,
       error => 'Communications error: ' . $response->status_line,
       statuscode => -1,
      };
  }
  my $result_content = $response->decoded_content;

  my $tree;
  eval {
    $tree = XMLin($result_content);
  };
  $@ and
    return { success => 0,
	     error => "Response parsing error: ".$@,
	     statuscode => -1 };

  if ($debug) {
    print STDERR "Raw response: $result_content\n";

    require Data::Dumper;
    Data::Dumper->import();
    print STDERR "Response parsed: ",Dumper($tree);
  }

  my $paranoid = $self->{paranoid};
  
  if ($paranoid) {
    # check the message id
    my $infotag = $tree->{MessageInfo}
      or return { success => 0, error=>'MessageInfo element not found', statuscode => -1 };

    $infotag->{messageID} eq $message_id
      or return { sucess => 0, error=>"MessageID doesn't match", 
		  statuscode=> -1 };
  }

  my $status_ele = $tree->{Status}
    or return { success => 0, error => 'Response missing Status element', statuscode => -1 };
  if ($status_ele->{statusCode} != 0) {
    return {
	    success => 0,
	    error => $status_ele->{statusDescription},
	    statuscode => $status_ele->{statusCode}
	   };
  }

  my $payment_ele = $tree->{Payment}
    or return { success => 0, error => 'Response missing Payment element', statuscode => -1 };
  my $txnlist_ele = $payment_ele->{TxnList}
    or return { success =>0, error => 'Response missiog TxnList element', statuscode => -1 };
  $txnlist_ele->{count} == 1
    or return { success => 0, error => 'Response has more or less than 1 transaction', statuscode => -1 };
  my $txn_ele = $txnlist_ele->{Txn}
    or return { success => 0, error => 'Response missing Txn element', statuscode => -1 };
  if ($txn_ele->{approved} eq 'Yes') {
    return
      {
       success => 1,
       statuscode => $txn_ele->{responseCode},
       error => $txn_ele->{responseText},
       receipt => $txn_ele->{txnID},
      };
  }
  else {
    return
      {
       success => 0,
       statuscode => $txn_ele->{responseCode},
       error => $txn_ele->{responseText},
      };
  }
}


1;

=head1 NAME

  DevHelp::Payments::SecurePayXML - the bottom level interface for talking to securepay via XML.

=head1 SYNOPSIS

  my $secpay = DevHelp::Payments::SecurePayXML->new($cfg);
  my $result = $secpay->payment(%parms);

=head1 DESCRIPTION

Implements the DevHelp::Payments interface for SecurePay's XML API.

=head1 CONFIGURATION

The following parameters can be set in the [securepay xml] section:

=over

=item test

If non-zero the driver works in test mode, including using the
testmerchantid, testpassword, testurl.

=item merchantid

=item password

Securepay issued id/password used to submit live transactions.

=item url

URL to submit live transactions.  Default:
https://www.securepay.com.au/xmlapi/payment

=item prefix

This is prefixed to the orderno parameter before it is passed to
SecurePay.

=item testmerchantid

=item testpassword

Merchant ID/password used in test mode.

=item testurl

URL used to submit test transactions.  Default:
https://www.securepay.com.au/test/payment

=item timeout

SecurePay backend timeout in seconds.  Default 60.

=item result_code

In test mode, if set, the cents part of any amount sent to securepay
is set to this value.  SecurePay will use the cents value of the
amount to set the returned result code from the test server.

=item debug

If non-zero debugging information is sent to STDERR.

=back

=cut
