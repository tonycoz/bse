package DevHelp::Payments::Inpho;
use strict;
use Carp 'confess';
use LWP::UserAgent;
use DevHelp::HTML;

sub new {
  my ($class, $cfg) = @_;

  return bless { cfg => $cfg }, $class;
}

sub payment {
  my ($self, %args) = @_;

  my $cfg = $self->{cfg};

  my $conf = $self->_conf;

  for my $name (qw/orderno amount cardnumber expirydate ipaddress cvv/) {
    defined $args{$name}
      or confess "Missing $name argument";
  }

  my ($expyear, $expmonth) = $args{expirydate} =~ /^(\d\d\d\d)(\d\d)$/
    or return
      {
       success => 0,
       statuscode => 1,
       error => 'Invalid expiry date',
      };

  my $currency = $args{currency};
  if (defined $currency && $currency ne 'AUD') {
    return
      {
       success => 0,
       error => 'Unknown currency',
       statuscode => 5,
      };
  }
  $currency = 'AUD';

  my $url = $conf->{url};
  my %url_args =
    (
     PAN => $args{cardnumber},
     expiry_month => $expmonth,
     expiry_year => sprintf("%02d", $expyear % 100),
     cardVerificationData => $args{cvv},
     currency_type => $currency,
     currency_amount => $args{amount},
     cardholderIP => $args{ipaddress},
     user_name => $conf->{user},
     user_password => $conf->{password},
    );
  $url .= '?' . join("&", map "$_=" . escape_uri($url_args{$_}), keys %url_args);
  
  my $ua = LWP::UserAgent->new;
  my $response = $ua->get($url);
  unless ($response->is_success) {
    return
      {
       success => 0,
       statuscode => 99,
       error => 'Error making request: '.$response->status_line,
      };
  }
  my $content = $response->content;
  if ($content eq '0') {
    return
      {
       success => 0,
       statuscode => 98,
       error => "Invalid request or invalid merchant user/password",
      };
  }

  # extract the fields from it
  my %result;
  for my $line (split /,/, $content) {
    if ($line =~ /^(\w+)=(.*)$/) {
      $result{$1} = $2;
    }
  }

  if ($result{SUMMARY_RESPONSE_CODE} != 0) {
    return
      {
       success => 0,
       statuscode => $result{RESPONSE_CODE},
       error => $result{RESPONSE_TEXT},
      };
  }

  # should be success
  return
    {
     success => 1,
     statuscode => $result{RESPONSE_CODE},
     error => $result{RESPONSE_TEXT},
     receipt => $result{RECEIPT_NUMBER},
     transactionid => $result{ORDER_NUMBER},
    };
}

my %norm_defs =
  (
   url => 'https://extranet.inpho.com.au/cc_ssl/process',
  );

my %test_defs =
  (
  );

sub _conf {
  my ($self) = @_;

  my $cfg = $self->{cfg};
  my $test = $cfg->entryBool('inpho', 'test');
  my $prefix = $test ? 'test_' : '';
  my $defs = $test ? \%test_defs : \%norm_defs;
  my %conf;
  for my $key (qw(url user password)) {
    my $value = $cfg->entry('inpho', $prefix.$key, $defs->{$key});
    defined $value
      or confess "Key $prefix$key not defined in [inpho] for credit card processing";
    $conf{$key} = $value;
  }

  \%conf;
}

1;
