package Courier::Fastway;

use strict;
use Courier;
use XML::Parser;

our @ISA = qw(Courier);

my $url = "http://www.fastwayfms.com/scripts/mgrqispi.dll";
my @fields =
    qw(APPNAME PRGNAME vXML Country CustFranCode pFranchisee
       vTown vPostcode vWeight vLength vHeight vWidth);

sub can_deliver {
    my ($self) = @_;

    return 0 unless defined $self->{order};
    return 0 if $self->{order}->{delivCountry} ne "Australia";
    return 1;
}

sub calculate_shipping {
    my ($self) = @_;

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
    $data{vPostcode} = $self->{order}->{delivPostCode};
    $data{vTown} = $self->{order}->{delivSuburb};

    $data{vWeight} = $self->{weight}/1000;
    foreach my $d (qw(length height width)) {
        my $v = $self->{$d};
        if (defined $v && $v) {
            $data{"v".ucfirst $d} = $v;
        }
    }

    if ($data{vWeight} > 25) {
        $self->{error} = "Parcel too heavy for this service.";
        return;
    }

    my $u = URI->new($url);
    $u->query_form(\%data);
    my $r = $self->{ua}->get($u);

    if ($r->is_success) {
        my $p = XML::Parser->new(
            Style => "Stream",
            Pkg => "Courier::Fastway::Parser"
        );
        eval { $p->parse($r->content) };
        unless ($@) {
            my $type = lc $self->{type};
            my $props = \%Courier::Fastway::Parser::props;
            if (exists $props->{$type}) {
                ($self->{cost} = $props->{$type}) =~ s/^.*to //;
                $self->{days} = $props->{days};
            }
            else {
                $self->{error} = $self->{type} . " service not available";
            }
        }
        else {
            warn $u->as_string(). ": $@\n";
            $self->{error} = "Server error";
        }
    }
    else {
        warn $u->as_string(). ": ". $r->status_line, "\n";
        $self->{error} = "Server error";
    }
}

package Courier::Fastway::Parser;

my $text;
my $capture;
my $service;
our %props;

sub StartTag {
    shift;
    if ($_[0] eq 'deltime' or
        $_[0] eq 'serv' or
        $_[0] eq 'price')
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
        elsif ($capture eq 'price') {
            $props{lc $service} = $text;
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
