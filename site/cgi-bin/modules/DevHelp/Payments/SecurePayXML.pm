package DevHelp::Payments::SecurePayXML;
use strict;
use Carp 'confess';
use Digest::MD5 qw(md5_hex);
use POSIX qw(strftime);
use LWP::UserAgent;
use XML::Parser;

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
  my $periodictesturl =  $cfg->entry('securepay xml', 'periodictesturl', 
			     "https://www.securepay.com.au/test/periodic");
  my $periodicliveurl =  $cfg->entry('securepay xml', 'url',
			     "https://www.securepay.com.au/xmlapi/periodic");
  my $timeout = $cfg->entry('securepay xml', 'timeout');
  my $testpassword = $cfg->entry('securepay xml', 'testpassword');
  my $livepassword = $cfg->entry('securepay xml', 'password');
  my $poprefix = $cfg->entry('securepay xml', 'prefix', '');
  my $periodic_prefix = $cfg->entry('securepay xml', 'periodic_prefix', '');
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
		periodicliveurl => $periodicliveurl,
		periodictesturl => $periodictesturl,
		timeout => $timeout,
		testpassword => $testpassword,
		livepassword => $livepassword,
		prefix => $poprefix,
		debug => $debug,
		result_code => $result_code,
		paranoid => $cfg->entry('securepay xml', 'paranoid', 1),
		periodic_prefix => $periodic_prefix,
	       }, $class;
}

sub _escape_xml {
  my ($text) = @_;

  $text =~ s/([<>&])/"&#".ord($1).";"/ge;

  return $text;
}

sub _request {
  my ($self, $tags, $template, $result, $xml_out) = @_;

  my $url = $self->{test} ? $self->{testurl} : $self->{liveurl};

  return $self->_request_low($tags, $template, $result, $xml_out, $url);
}

sub _request_periodic {
  my ($self, $tags, $template, $result, $xml_out) = @_;

  my $url = $self->{test} ? $self->{periodictesturl} : $self->{periodicliveurl};

  return $self->_request_low($tags, $template, $result, $xml_out, $url);
}

sub _request_low {
  my ($self, $tags, $template, $result, $xml_out, $url) = @_;

  # set some standard tags
  if ($self->{test}) {
    $tags->{merchantid} = $self->{testmerchantid};
    $tags->{password} = $self->{testpassword};
  }
  else {
    $tags->{merchantid} = $self->{livemerchantid};
    $tags->{password} = $self->{livepassword};
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
      if $self->{debug};
    $tz_offset = '+000';
  }
  $tags->{timestamp} = strftime("%Y%d%m%H%M%S000000", localtime) . $tz_offset;
  $tags->{timeout} = $self->{timeout} || 60;

  # md5_hex returns a 32 char str, max is meant to be 30
  my $message_id = md5_hex(++$sequence . time(), $$);
  substr($message_id, 30) = '';
  $tags->{messageid} = $message_id;

  my $xml = $template;
  eval {
    $xml =~ s/<:(\w+):>/exists $tags->{$1} ? $tags->{$1} : die "Key $1 not found" /ge;
  };
  if ($@) {
    $$result =
      {
       success => 0,
       error => 'Internal error: '. $@,
       statuscode => -1,
      };
    return;
  }

  my $ua = LWP::UserAgent->new;
  my $http_request = HTTP::Request->new(POST => $url);

  if ($self->{debug}) {
    print STDERR "Raw request: $xml\n";
    print STDERR "Url: $url\n";
  }

  $http_request->content($xml);
  my $response = $ua->request($http_request);
  unless ($response->is_success) {
    $$result =
      {
       success => 0,
       error => 'Communications error: ' . $response->status_line,
       statuscode => -1,
      };
    return;
  }
  my $result_content = $response->decoded_content;

  if ($self->{debug}) {
    print STDERR "Raw response: $result_content\n";
  }

  my $toptree;
  eval {
    my $parser = XML::Parser->new(Style => 'Tree');
    $toptree = $parser->parse($result_content);
  };
  if ($@) {
    $$result =
      {
       success => 0,
       error => "Response parsing error: ".$@,
       statuscode => -1 
      };
    return;
  }

  if ($self->{debug}) {
    require Data::Dumper;
    Data::Dumper->import();
    print STDERR "Response parsed: ",Dumper($toptree);
  }

  my $paranoid = $self->{paranoid};

  if ($paranoid && $toptree->[0] ne 'SecurePayMessage') {
    $$result = 
      {
       success => 0,
       error => 'Root element not SecurePayMessage',
       statuscode => -1,
      };
  }

  my $tree = $toptree->[1];
  
  if ($paranoid) {
    # check the message id
    my $infotag = _find_element($tree, 'MessageInfo');
    unless ($infotag) {
      $$result =
	{ 
	 success => 0, 
	 error=>'MessageInfo element not found', 
	 statuscode => -1
	};
      return;
    }
    
    # extract the message id
    my $parse_message_id = _find_value($infotag, 'messageID');
    
    unless ($parse_message_id && $parse_message_id eq $message_id) {
      $$result =
	{ 
	 sucess => 0, 
	 error=>"messageID doesn't match", 
	 statuscode=> -1 
	};
      return;
    }
  }

  $$xml_out = $tree;

  return 1;
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

sub _find_element {
  my ($tree, $tag) = @_;

  my $index = 1;
  while ($index < @$tree) {
    if ($tree->[$index] eq $tag) {
      return $tree->[$index+1];
    }
    ++$index;
  }

  return;
}

# extract the plain text value of an element
# returns () if not found or if the element isn't a plain value
sub _find_value {
  my ($tree, $tag) = @_;

  my $element = _find_element($tree, $tag)
    or return;
  @$element == 3 && $element->[1] == 0
    or return;

  return $element->[1];
}

# returns status code, status description as a list
sub _extract_status {
  my ($tree) = @_;
  
  my $status = _find_element($tree, 'Status')
    or return;

  return (
	  scalar(_find_value($status, 'statusCode')),
	  scalar(_find_value($status, 'statusDescription'))
	 );
}

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

  # yet another templating system, if we ever need something more
  # sophisticated than this here switch to Squirrel::Template
  my %replace =
    (
     expirydate => $args{expirydate},
     amount => $amount,
     orderno => $orderno,
     cardnumber => $args{cardnumber},
     currency => $args{currency} || 'AUD',
     cvvtag => '',
    );
  
  # XML escape all of these
  for my $value (values %replace) {
    $value = _escape_xml($value);
  }

  # but not these
  if ($args{cvv}) {
    $replace{cvvtag} = "<cvv>$args{cvv}</cvv>";
  }

  my $tree;
  my $result; # set to a result hashref on failure

  $self->_request(\%replace, $payment_template, \$result, \$tree)
    or return $result;

  my ($status_code, $status_desc) = _extract_status($tree)
    or return { success => 0, error => 'Response missing Status element', statuscode => -1 };
  if ($status_code != 0) {
    return {
	    success => 0,
	    error => $status_desc,
	    statuscode => $status_code
	   };
  }

  my $payment_ele = _find_element($tree, 'Payment')
    or return { success => 0, error => 'Response missing Payment element', statuscode => -1 };
  my $txnlist_ele = _find_element($payment_ele, 'TxnList')
    or return { success =>0, error => 'Response missiog TxnList element', statuscode => -1 };
  $txnlist_ele->[0]{count} == 1
    or return { success => 0, error => 'Response has more or less than 1 transaction', statuscode => -1 };
  my $txn_ele = _find_element($txnlist_ele,, 'Txn')
    or return { success => 0, error => 'Response missing Txn element', statuscode => -1 };
  if (_find_value($txn_ele, 'approved') eq 'Yes') {
    return
      {
       success => 1,
       statuscode => scalar(_find_value($txn_ele, 'responseCode')),
       error => scalar(_find_value($txn_ele, 'responseText')),
       receipt => scalar(_find_value($txn_ele, 'txnID')),
      };
  }
  else {
    return
      {
       success => 0,
       statuscode => scalar(_find_value($txn_ele, 'responseCode')),
       error => scalar(_find_value($txn_ele, 'responseText')),
      };
  }
}

my $add_template = <<'XML';
<?xml version="1.0" encoding="UTF-8"?>
<SecurePayMessage>
  <MessageInfo>
    <messageID><:messageid:></messageID>
    <messageTimestamp><:timestamp:></messageTimestamp>
    <timeoutValue><:timeout:></timeoutValue>
    <apiVersion>spxml-3.0</apiVersion>
  </MessageInfo>
  <MerchantInfo>
    <merchantID><:merchantid:></merchantID>
    <password><:password:></password>
  </MerchantInfo>
  <RequestType>Periodic</RequestType>
  <Periodic>
    <PeriodicList count="1">
      <PeriodicItem ID="1">
        <actionType>add</actionType>
        <clientID><:clientid:></clientID>
        <CreditCardInfo>
          <cardNumber><:cardnumber:></cardNumber>
          <expiryDate><:expirydate:></expiryDate>
<:cvvtag:>
        </CreditCardInfo>
        <amount>1000</amount>
        <periodicType>4</periodicType>
      </PeriodicItem>
    </PeriodicList>
  </Periodic>
</SecurePayMessage>
XML

sub add_payment {
  my ($self, %args) = @_;

  for my $name (qw/clientid cardnumber expirydate/) {
    defined $args{$name}
      or confess "Missing $name argument";
  }

  my $clientid = $self->{periodic_prefix} . $args{clientid} . 'x' . time();

  my %replace =
    (
     clientid => _escape_xml($clientid),
     expirydate => $args{expirydate},
     cardnumber => $args{cardnumber},
     currency => $args{currency} || 'AUD',
     cvvtag => '',
    );

  if ($args{cvv}) {
    $replace{cvvtag} = "<cvv>$args{cvv}</cvv>";
  }

  my $result;
  my $tree;
  $self->_request_periodic(\%replace, $add_template, \$result, \$tree)
    or return $result;

  my $status_ele = $tree->{Status}
    or return { success => 0, error => 'Response missing Status element', statuscode => -1 };
  if ($status_ele->{statusCode} != 0) {
    return {
	    success => 0,
	    error => $status_ele->{statusDescription},
	    statuscode => $status_ele->{statusCode}
	   };
  }

  my $periodic_ele = $tree->{Periodic}
    or return 
      {
       success => 0,
       error => 'Response missing Periodic element',
       statuscode => -1,
      };
  my $list_ele = $periodic_ele->{PeriodicList}
    or return 
      {
       success => 0,
       error => 'Response missing PeriodicList element',
       statuscode => -1,
      };
  my $item_ele = $list_ele->{PeriodicItem}
    or return 
      {
       success => 0,
       error => 'Response missing PeriodicItem element',
       statuscode => -1,
      };
  if (lc($item_ele->{successful}) eq 'yes') {
    return
      {
       success => 1,
       paymentid => $clientid,
       statuscode => $item_ele->{responseCode} || '',
       error => $item_ele->{responseText} || '',
      };
  }
  else {
    return
      {
       success => 0,
       statuscode => $item_ele->{responseCode} || '',
       error => $item_ele->{responseText} || '',
      };
  }
}

my $trigger_template = <<'XML';
<?xml version="1.0" encoding="UTF-8"?>
<SecurePayMessage>
  <MessageInfo>
    <messageID><:messageid:></messageID>
    <messageTimestamp><:timestamp:></messageTimestamp>
    <timeoutValue><:timeout:></timeoutValue>
    <apiVersion>spxml-3.0</apiVersion>
  </MessageInfo>
  <MerchantInfo>
    <merchantID><:merchantid:></merchantID>
    <password><:password:></password>
  </MerchantInfo>
  <RequestType>Periodic</RequestType>
  <Periodic>
    <PeriodicList count="1">
      <PeriodicItem ID="1">
        <actionType>trigger</actionType>
        <clientID><:clientid:></clientID>
        <amount><:amount:></amount>
      </PeriodicItem>
    </PeriodicList>
  </Periodic>
</SecurePayMessage>
XML

sub make_payment {
  my ($self, %args) = @_;

  for my $name (qw/paymentid amount/) {
    defined $args{$name}
      or confess "Missing $name argument";
  }

  my %replace =
    (
     clientid => _escape_xml($args{paymentid}),
     amount => _escape_xml($args{amount}),
     currency => $args{currency} || 'AUD',
    );

  my $result;
  my $tree;
  $self->_request_periodic(\%replace, $trigger_template, \$result, \$tree)
    or return $result;

  my $status_ele = $tree->{Status}
    or return { success => 0, error => 'Response missing Status element', statuscode => -1 };
  if ($status_ele->{statusCode} != 0) {
    return {
	    success => 0,
	    error => $status_ele->{statusDescription},
	    statuscode => $status_ele->{statusCode}
	   };
  }

  my $periodic_ele = $tree->{Periodic}
    or return 
      {
       success => 0,
       error => 'Response missing Periodic element',
       statuscode => -1,
      };
  my $list_ele = $periodic_ele->{PeriodicList}
    or return 
      {
       success => 0,
       error => 'Response missing PeriodicList element',
       statuscode => -1,
      };
  my $item_ele = $list_ele->{PeriodicItem}
    or return 
      {
       success => 0,
       error => 'Response missing PeriodicItem element',
       statuscode => -1,
      };
  if (lc($item_ele->{successful}) eq 'yes') {
    return
      {
       success => 1,
       receipt => $item_ele->{txnID},
       statuscode => $item_ele->{responseCode} || '',
       error => $item_ele->{responseText} || '',
      };
  }
  else {
    return
      {
       success => 0,
       statuscode => $item_ele->{responseCode} || '',
       error => $item_ele->{responseText} || '',
      };
  }
}

my $delete_template = <<'XML';
<?xml version="1.0" encoding="UTF-8"?>
<SecurePayMessage>
  <MessageInfo>
    <messageID><:messageid:></messageID>
    <messageTimestamp><:timestamp:></messageTimestamp>
    <timeoutValue><:timeout:></timeoutValue>
    <apiVersion>spxml-3.0</apiVersion>
  </MessageInfo>
  <MerchantInfo>
    <merchantID><:merchantid:></merchantID>
    <password><:password:></password>
  </MerchantInfo>
  <RequestType>Periodic</RequestType>
  <Periodic>
    <PeriodicList count="1">
      <PeriodicItem ID="1">
        <actionType>delete</actionType>
        <clientID><:clientid:></clientID>
      </PeriodicItem>
    </PeriodicList>
  </Periodic>
</SecurePayMessage>
XML

sub delete_payment {
  my ($self, %args) = @_;

  for my $name (qw/paymentid/) {
    defined $args{$name}
      or confess "Missing $name argument";
  }

  my %replace =
    (
     clientid => _escape_xml($args{paymentid}),
    );

  my $result;
  my $tree;
  $self->_request_periodic(\%replace, $delete_template, \$result, \$tree)
    or return $result;

  my $status_ele = $tree->{Status}
    or return { success => 0, error => 'Response missing Status element', statuscode => -1 };
  if ($status_ele->{statusCode} != 0) {
    return {
	    success => 0,
	    error => $status_ele->{statusDescription},
	    statuscode => $status_ele->{statusCode}
	   };
  }

  my $periodic_ele = $tree->{Periodic}
    or return 
      {
       success => 0,
       error => 'Response missing Periodic element',
       statuscode => -1,
      };
  my $list_ele = $periodic_ele->{PeriodicList}
    or return 
      {
       success => 0,
       error => 'Response missing PeriodicList element',
       statuscode => -1,
      };
  my $item_ele = $list_ele->{PeriodicItem}
    or return 
      {
       success => 0,
       error => 'Response missing PeriodicItem element',
       statuscode => -1,
      };
  if (lc($item_ele->{successful}) eq 'yes') {
    return
      {
       success => 1,
       statuscode => $item_ele->{responseCode} || '',
       error => $item_ele->{responseText} || '',
      };
  }
  else {
    return
      {
       success => 0,
       statuscode => $item_ele->{responseCode} || '',
       error => $item_ele->{responseText} || '',
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
