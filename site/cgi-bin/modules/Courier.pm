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
        my $number = $item->{units};

        my $weight = $product->{weight};
        if ($weight == 0) {
            $totalWeight = 0;
            last;
        }
        $totalWeight += $weight*$number;

        # Calculate dimensions for the given number of items. We keep
        # filling a stack of n*n squares with products, and measure the
        # stack.

        my ($L, $W, $H) =
            @{$product}{qw(length width height)};
        my ($length, $width, $height) = ($L, $W, $H);
 
        $number--;
        my $i = 0;
        while ($number > 0) {
            my $n = $i++ % 3;
            if ($n == 0) { $length += $L; }
            elsif ($n == 1) { $width += $W; }
            elsif ($n == 2) { $height += $H; }
            $number >>= 1;
        }

        # Store the longest length and width of any group of items in
        # the order, but keep adding up the heights. Represents
        # something like a worst-case packing.

        if ($length != 0 && $length > $self->{length}) {
            $self->{length} = $length;
        }

        if ($width != 0 && $width > $self->{width}) {
            $self->{width} = $width;
        }

        $self->{height} += $height;
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

    my $cost = $self->{cost};
    if ($cost) {
        # We can't be sure what sort of number the courier returned.
        if ($cost =~ m/\...$/) {
            $cost =~ s/\.//;
        }
        else {
            $cost *= 100;
        }
    }
    return $cost;
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
    my ($cfg, $wanted) = @_;

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
        next if defined $wanted and $wanted ne $courier->name();
        push @couriers, $courier;
    }
    return @couriers;
}

1;
