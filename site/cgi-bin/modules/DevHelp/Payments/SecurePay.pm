package DevHelp::Payments::SecurePay;
use strict;
use Config;
use Carp 'confess';

sub new {
  my ($class, $cfg) = @_;

  my $debug = $cfg->entry('securepay', 'debug', 0);

  # setup the environment
  my $sep = $Config{path_sep};
  for my $var (qw/CLASSPATH PATH LD_LIBRARY_PATH/) {
    my $value = $cfg->entry("securepay", "\L$var");
    if ($ENV{$var}) {
      $ENV{$var} = $value . $sep . $ENV{$var};
    }
    else {
      $ENV{$var} = $value;
    }
  }
  my $java_port = $cfg->entry('securepay', 'java_port', 8765);
  my $directory = $cfg->entryErr('securepay', 'java_directory');
  my %args =
    (
     SHARED_JVM => 1,
     PORT => $java_port,
     DIRECTORY => $directory,
    );
  $args{CLASSPATH} = $cfg->entry("securepay", $ENV{CLASSPATH})
    if $ENV{CLASSPATH};
  $args{DEBUG} = $debug if $debug;
  require Inline;
  Inline->import
       (
        Java => 'STUDY',
        STUDY => [ qw/securepay.jxa.api.Payment securepay.jxa.api.Txn/ ],
	%args,
       );
  #use Data::Dumper;
  #print Dumper \%BSE::SecurePay::securepay::jxa::api::Payment::;

  my $test = $cfg->entry('securepay', 'test', 1);
  my $livemerchantid = $cfg->entry('securepay', 'merchantid');
  my $testmerchantid = $cfg->entry('securepay', 'testmerchantid');
  my $testurl =  $cfg->entry('securepay', 'testperiodicurl', 
			     "https://www.securepay.com.au/test/payment");
  my $liveurl =  $cfg->entry('securepay', 'periodicurl',
			     "https://www.securepay.com.au/xmlapi/payment");
  my $timeout = $cfg->entry('securepay', 'timeout');
  my $testpassword = $cfg->entry('securepay', 'testpassword');
  my $livepassword = $cfg->entry('securepay', 'password');
  my $poprefix = $cfg->entry('securepay', 'prefix', '');
  if ($debug) {
    print STDERR "SecurePay Config:\n",
      "  test: $test\n  url: $testurl - $liveurl\n  merchantid: $testmerchantid - $livemerchantid\n  timeout:",
	defined($timeout) ? $timeout : "undef", "\n  prefix: $poprefix\n";
       
  }
  my $result_code = $cfg->entry('securepay', 'result_code');
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
	       }, $class;
}

sub payment {
  my ($self, %args) = @_;

  for my $name (qw/orderno amount cardnumber expirydate/) {
    defined $args{$name}
      or confess "Missing $name argument";
  }

  my $orderno = $self->{prefix} . $args{orderno};

  my $amount = $args{amount};
  if ($self->{test} && defined($self->{result_code})) {
    $amount = 100 * int($amount / 100) + $self->{result_code};
  }

  if ($args{expirydate} =~ /^(\d\d\d\d)(\d\d)$/) {
    $args{expirydate} = sprintf("%02d/%02d", $2, $1 %100);
  }

  my $if = $self->_interface($args{test});
  my $txn = $if->addTxn(0, $orderno);
  $txn->setTxnSource(0);
  $txn->setAmount($amount);
  $txn->setCardNumber($args{cardnumber});
  $txn->setExpiryDate($args{expirydate});

  my $test = $args{test} || $self->{test};
  my $password = $test ? $self->{testpassword} : $self->{livepassword};
  my $processed = $if->process($password);

  if ($processed) {
    my $resp = $if->getTxn(0);
    if ($self->{debug}) {
      print STDERR "Sent Status: ",$if->getStatusCode(),"\n";
      print STDERR "Desc: ",$if->getStatusDesc(),"\n";
    }
    print STDERR "Approved: ",$resp->getApproved,"\n";
    return 
      {
       success => $resp->getApproved,
       statuscode => $resp->getResponseCode(),
       error => $resp->getResponseText(),
       receipt => $resp->getTxnId(),
      };
  }
  else {
    if ($self->{debug}) {
      print STDERR "Fail Status: ",$if->getStatusCode(),"\n";
      print STDERR "Desc: ",$if->getStatusDesc(),"\n";
    }
    return {
	    success => 0,
	    statuscode => $if->getStatusCode(),
	    error => $if->getStatusDesc(),
	   };
  }
}

sub _interface {
  my ($self, $test) = @_;

  $test ||= $self->{test};
  my $url = $test ? $self->{testurl} : $self->{liveurl};
  print STDERR "URL: $url\n" if $self->{debug};
  my $merchantid = $test ? $self->{testmerchantid} : $self->{livemerchantid};

  print STDERR "MerchantID: $merchantid\n" if $self->{debug};
  my $if = DevHelp::Payments::SecurePay::securepay::jxa::api::Payment->new;
  $if->setMerchantId($merchantid);
  $if->setServerURL($url);
  $if->setProcessTimeout($self->{timeout}) if $self->{timeout};

  $if;
}



1;

=head1 NAME

  BSE::SecurePay - the bottom level interface for talking to securepay.

=head1 SYNOPSIS

  my $secpay = BSE::SecurePay->new($cfg);
  my $result = $secpay->payment(%parms);
  $result = $secpay->preauth(%parms);
  $result = $secpay->complete(%parms);

=head1 DESCRIPTION

There will be more here.

=cut
