package Courier::AustraliaPost;

use strict;
use Courier;
use BSE::Countries qw(bse_country_code);
use Carp qw(confess);

our @ISA = qw(Courier);

my $url = "http://drc.edeliver.com.au/ratecalc.asp";
my @fields =
    qw(Pickup_Postcode Destination_Postcode Country
       Weight Service_Type Length Width Height Quantity);

sub can_deliver {
    return 1;
}

sub calculate_shipping {
  my ($self, %opts) = @_;
  
  my $trace = '';

  my $parcels = $opts{parcels}
    or confess "Missing parcels parameter";
  my $suburb = $opts{suburb}
    or confess "Missing suburb paramater";
  my $postcode = $opts{postcode}
    or confess "Missing postcode parameter";
  my $country = $opts{country}
    or confess "Missing country parameter";

  my $country_code = bse_country_code($country);
  unless ($country_code) {
    $self->{error} = "Unknown country";
    return;
  }

  my $source_postcode = $self->{config}->entry("shipping", "sourcepostcode");
  unless ($source_postcode) {
    $self->{error} = "Configuration error: shipping.sourcepostcode not set";
    return;
  }

  my $total_cost;
  for my $parcel (@$parcels) {
    my %data = ();
    
    $data{Service_Type} = $self->{type};
    $data{Pickup_Postcode} = $source_postcode;
      
    $data{Destination_Postcode} = $postcode;
    $data{Country} = $country_code;
    $data{Quantity} = 1;
    $data{Weight} = $parcel->weight;

    my $l = $parcel->length;
    my $w = $parcel->width;
    my $h = $parcel->height;
    if ($l < 50 && not ($w >= 50 and $h >= 50)) {
      $l = 50;
    }
    if ($w < 50 && not ($l >= 50 and $h >= 50)) {
      $w = 50;
    }
    @data{qw(Length Width Height)} = ($l, $w, $h);

    my $u = URI->new($url);
    
    $trace .= "Request URL: $u\nPosted:\n";
    $trace .= " $_: $data{$_}\n" for keys %data;
    $trace .= "\n";
    
    my $r = $self->{ua}->post($u, \%data);
    if ($r->is_success) {
      $trace .= "Success: [\n" . $r->content . "\n]\n";
      my @lines = split /\r?\n/, $r->content;
      my $error;
      my $cost;
      foreach (@lines) {
	if (/^charge=(.*)$/) {
	  $cost = $1 * 100;
	} elsif (/^days=(.*)$/) {
	  $self->{days} = $1;
	} elsif (/^err_msg=(.*)$/) {
	  $error = $1;
	}
      }
      if ($error eq "OK") {
	$total_cost += $cost;
      }
      else {
	$self->{error} = $error;
	warn "AustraliaPost error: ",
	  $self->{error}, " (",
	    join(", ", map { "$_ => '$data{$_}'" } keys %data),
	      ")\n";
	return;
      }
    } else {
      $trace .= "Error: ". $r->status_line . "\n";
      warn $u->as_string(). ": ". $r->status_line, "\n";
      $self->{error} = "Server error";
      return;
    }
  }
  $self->{trace} = $trace;
  
  return $total_cost;
}

1;
