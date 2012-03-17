package Courier::Fastway;

our $VERSION = "1.001";

use strict;
use Courier;
use XML::Parser;
use Carp qw(confess);

our @ISA = qw(Courier);

my $url = "http://www.fastwayfms.com/scripts/mgrqispi.dll";
my @fields =
    qw(APPNAME PRGNAME vXML Country CustFranCode pFranchisee
       vTown vPostcode vWeight vLength vHeight vWidth);

sub new {
  my $class = shift;
  my $self = $class->SUPER::new(@_);

  $self->{frequent} = $self->{config}->entry('shipping', 'fastwayfrequent', 0);

  return $self;
}

sub can_deliver {
    my ($self, %opts) = @_;

    my $country = $opts{country}
      or return 0;

    return 0 if lc $country ne "au";

    return 1;
}

sub calculate_shipping {
    my ($self, %opts) = @_;

    my $parcels = $opts{parcels}
      or confess "Missing parcels parameter";
    my $suburb = $opts{suburb}
      or confess "Missing suburb paramater";
    my $postcode = $opts{postcode}
      or confess "Missing postcode parameter";

    my $debug = $self->{config}->entry("debug", "fastway", 0);

    undef $self->{error};

    my $total_cost = 0;
    my $trace = '';
      
    for my $parcel (@$parcels) {
      my %data = (
		  APPNAME => "FW",
		  PRGNAME => "FastLocatorResult",
		  vXML => 1,
		  Country => 1,
		 );
      
      $data{CustFranCode} =
        $self->{config}->entry("shipping", "fastwayfranchiseecode") || "";
      $data{pFranchisee} =
        $self->{config}->entry("shipping", "fastwayfranchisee");
      $data{vPostcode} = $postcode;
      $data{vTown} = $suburb;
      
      $data{vWeight} = int($parcel->weight / 1000 + 0.5);
      foreach my $d (qw(length height width)) {
        my $v = $parcel->$d;
        if (defined $v && $v) {
	  $data{"v".ucfirst $d} = int($v/10+0.5);
        }
      }

      my $cubic_weight = int( $parcel->cubic_weight / 1000 + 0.5);
      if ($cubic_weight > $data{vWeight}) {
        $data{vWeight} = $cubic_weight;
      }

      if ($data{vWeight} > $self->weight_limit) {
        $self->{error} = "Parcel too heavy for this service.";
        return;
      }

      my $u = URI->new($url);
      $u->query_form(\%data);
      my $r = $self->{ua}->get($u);
      
      $trace .= "Request url: $u\n";
      
      $debug and print STDERR "Fastway request: $u\n";
      
      if ($r->is_success) {
        $debug and print STDERR "Success: [",$r->content,"]\n";
        $trace .= "Response: [\n" . $r->content . "\n]\n";
	%Courier::Fastway::Parser::props = ();
        my $p = XML::Parser->new(
            Style => "Stream",
            Pkg => "Courier::Fastway::Parser"
        );
        eval { $p->parse($r->content) };
        unless ($@) {
	  my $type = lc $self->{type};
	  my $props = \%Courier::Fastway::Parser::props;
	  my $result = $self->_find_result($props);
	  if ($result
	      and exists $result->{price}
	      and exists $result->{totalprice}) {
	    my $cost = $self->_extract_price($result->{price});
	    my $extra = $self->_extract_price($result->{totalprice});
	    unless ($cost) {
	      $self->{error} = "Service not available";
	      return;
	    }
	    $extra and $cost += $extra;
	    $total_cost += $cost;
	    $self->{days} = $props->{days};
	  }
	  else {
	    $self->{error} = $self->description . " not available to this location (check your postcode)";
	    return;
	  }
        }
        else {
	  warn $u->as_string(). ": $@\n";
	  $self->{error} = "Server error";
	  return;
        }
      }
      else {
        $trace .= "Error: ". $r->status_line . "\n";
	$debug and print STDERR "Failure: [",$r->status_line,"]\n";
        warn $u->as_string(). ": ". $r->status_line, "\n";
        $self->{error} = "Server error";
	return;
      }
    }
    $self->{trace} = $trace;
    
    return $total_cost;
}

# the price and totalprice fields are formatted:
#  $\s*(\d+.\d\d) - $\s*(\d+.\d\d)
# where the first price is the frequent user price and the second the
# standard user price
#
# parse such a price, extra the appropriate field scaled to cents.
# returns nothing on failure.

sub _extract_price {
  my ($self, $value) = @_;

  $value =~ /^\s*\$?\s*(\d+\.\d\d)\s*(?:-|to)\s*\$?\s*(\d+\.\d\d)\s*$/
    or return;

  my $price_dollars = $self->{frequent} ? $1 : $2;

  return 100 * $price_dollars;
}

# derived class must implement:
#   weight_limit - limit in kg for the service

package Courier::Fastway::Parser;

my $text;
my $capture;
my $service;
our %props;

sub StartTag {
    shift;
    if ($_[0] eq 'deltime' or
        $_[0] eq 'serv' or
        $_[0] eq 'price' or
        $_[0] eq 'totalprice')
    {
        $capture = $_[0];
    }
}

sub EndTag {
    if ($capture) {
        $text =~ s/^\s*|\s*$//;
        if ($capture eq 'deltime') {
            $props{days} = $text;
        }
        elsif ($capture eq 'serv') {
            $service = $text;
        }
	elsif ($capture eq 'totalprice') {
	    # total price of extra labels to add
            $props{lc $service}{totalprice} = $text;
	}
        elsif ($capture eq 'price') {
            $props{lc $service}{price} = $text;
        }
        $capture = 0;
        $text = "";
    }
}

sub Text {
    if ($capture) {
        $text .= $_;
    }
}

1;
