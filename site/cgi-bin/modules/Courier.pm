package Courier;

use strict;
use Products;
use LWP::UserAgent;

sub new {
    my $class = shift;
    my $self = {};
    my %args = @_;

    @$self{qw(cost days error)} = undef;
    $self->{config} = $args{config};
    $self->{type} = $args{type};
    $self->{ua} = LWP::UserAgent->new;
    return bless $self, $class;
}

sub name {
    # Implemented by subclasses
}

sub description {
    # Implemented by subclasses
}

sub set_order {
    my ($self, $order, $items) = @_;

    $self->{order} = $order;
    $self->{length} = 0;
    $self->{height} = 0;
    $self->{width} = 0;

    my $totalWeight = 0;
    foreach my $item (@$items) {
        my $product = Products->getByPkey($item->{productId});

        my $weight = $product->{weight};
        if ($weight == 0) {
            $totalWeight = 0;
            last;
        }
        $totalWeight += $weight*$item->{units};

        # Store the longest length and width of any item in the order,
        # but keep adding up the heights. Represents something like a
        # worst-case packing.

        my $length = $product->{length};
        if ($length != 0 && $length > $self->{length}) {
            $self->{length} = $length;
        }

        my $width = $product->{width};
        if ($width != 0 && $width > $self->{width}) {
            $self->{width} = $width;
        }

        $self->{height} += $product->{height};
    }
    $self->{weight} = $totalWeight;
}

sub can_deliver {
    # Implemented by subclasses
    return 0;
}

sub calculate_shipping {
    # Implemented by subclasses
}

sub shipping_cost {
    my ($self) = @_;
    return $self->{cost};
}

sub delivery_in {
    my ($self) = @_;
    return $self->{days};
}

sub error_message {
    my ($self) = @_;
    return $self->{error};
}

sub get_couriers {
    my ($cfg) = @_;

    my @couriers;
    foreach my $name (split /\s+/, $cfg->entry("shipping", "couriers")) {
        $name = "Courier::$name";
        (my $file = $name) =~ s/::/\//g;
        $file .= ".pm";

        my $courier;
        eval {
            require $file;
            $courier = $name->new(config => $cfg);
        };
        if ($@) {
            warn "Unable to load $courier: $@\n";
            next;
        }
        push @couriers, $courier;
    }
    return @couriers;
}

1;
