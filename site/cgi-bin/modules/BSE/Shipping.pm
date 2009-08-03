package BSE::Shipping;
use strict;
use Carp qw(confess);

sub get_couriers {
    my ($class, $cfg, $wanted) = @_;

    my @enabled = split /\s+/, $cfg->entry("shipping", "couriers");
    push @enabled, "Null";

    my @couriers;
    foreach my $name (@enabled) {
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

# returns one or more parcels to be delivered by a courier
# currently always returns a single parcel
sub package_order {
    my ($class, $cfg, $order, $items) = @_;

    require Products;
    my $total_weight = 0;
    my $total_length = 0;
    my $total_width = 0;
    my $total_height = 0;
    foreach my $item (@$items) {
        my $product = Products->getByPkey($item->{productId});
        my $number = $item->{units};

        my $weight = $product->{weight};
        $weight == 0
	  and next;

        $total_weight += $weight*$number;

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

        if ($length != 0 && $length > $total_length) {
            $total_length = $length;
        }

        if ($width != 0 && $width > $total_width) {
            $total_width = $width;
        }

        $total_height += $height;
    }

    wantarray
      or confess "package_order() may return multiple packages in the future";

    return BSE::Shipping::Parcel->new
      (
       length => $total_length,
       width => $total_width,
       height => $total_height,
       weight => $total_weight
      );
}

package BSE::Shipping::Parcel;
use strict;
use Carp qw(confess);

# simple wrapper around length/width/height/weight

sub new {
  my ($class, %opts) = @_;

  defined $opts{length}
    or confess "Missing length option";
  defined $opts{width}
    or confess "Missing width option";
  defined $opts{height}
    or confess "Missing height option";
  defined $opts{weight}
    or confess "Missing weight option";

  return bless \%opts, $class;
}

# calcuate "cubic weight" as per Australia Post
# as volume in cubic metres * 250
# length/width/height in millimetres
# result is in grams
sub cubic_weight {
  my $self = shift;
  $self->length / 1000 * $self->width / 1000 * $self->height / 1000 * 250_000;
}

sub length {
  $_[0]{length};
}

sub width {
  $_[0]{width};
}

sub height {
  $_[0]{height};
}

sub weight {
  $_[0]{weight};
}

1;

