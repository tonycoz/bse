package Courier::Fastway;

use strict;
use Courier;
use XML::Parser;

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
    my ($self) = @_;

    return 0 unless defined $self->{order};
    return 0 if $self->{order}->{delivCountry} ne "Australia";
    return 1;
}

sub calculate_shipping {
    my ($self) = @_;

    my $debug = $self->{config}->entry("debug", "fastway", 0);

    my %data = (
        APPNAME => "FW",
        PRGNAME => "FastLocatorResult",
        vXML => 1,
        Country => 1,
    );

    my $trace = '';

    $data{CustFranCode} =
        $self->{config}->entry("shipping", "fastwayfranchiseecode") || "";
    $data{pFranchisee} =
        $self->{config}->entry("shipping", "fastwayfranchisee");
    $data{vPostcode} = $self->{order}->{delivPostCode};
    $data{vTown} = $self->{order}->{delivSuburb};

    $data{vWeight} = int($self->{weight}/1000+0.5);
    foreach my $d (qw(length height width)) {
        my $v = $self->{$d};
        if (defined $v && $v) {
            $data{"v".ucfirst $d} = int($v/10+0.5);
        }
    }

    my $cubic_weight =
        (($data{vLength}/100)*($data{vWidth}/100)*($data{vHeight}/100))*250;
    if ($cubic_weight > $data{vWeight}) {
        $data{vWeight} = int($cubic_weight+0.5);
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
        my $p = XML::Parser->new(
            Style => "Stream",
            Pkg => "Courier::Fastway::Parser"
        );
        eval { $p->parse($r->content) };
        unless ($@) {
            my $type = lc $self->{type};
            my $props = \%Courier::Fastway::Parser::props;
            if (exists $props->{$type}
		and exists $props->{$type}{price}
		and exists $props->{$type}{totalprice}) {
		my $cost = $self->_extract_price($props->{$type}{price});
	        my $extra = $self->_extract_price($props->{$type}{totalprice});
		$extra and $cost += $extra;
                $self->{cost} = $cost;
                $self->{days} = $props->{days};
            }
            else {
                $self->{error} = $self->{type} . " service not available to this location (check your postcode)";
            }
        }
        else {
            warn $u->as_string(). ": $@\n";
            $self->{error} = "Server error";
        }
    }
    else {
        $trace .= "Error: ". $r->status_line . "\n";
	$debug and print STDERR "Failure: [",$r->status_line,"]\n";
        warn $u->as_string(). ": ". $r->status_line, "\n";
        $self->{error} = "Server error";
    }
    $self->{trace} = $trace;
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
