package BSE::TB::Subscription::Calc;
use strict;
use BSE::Util::SQL qw(:datemath);

# this code is here to allow testing of it without having real data
# in the database.

sub calculate_period {
  my ($class, $debug, @sub_info) = @_;
  
  my $start = sql_normal_date($sub_info[0]{orderDate});
  my $duration = 0;
  my $max_lapsed = 0;
  my $end = $start;
  
  my @periods = (
		 {
		  start => $start,
		  duration => 0,
		  end => $end,
		  order_ids => [],
		  product_ids => [],
		  item_ids => [],
		  max_lapsed => 0,
		 }
		);
  
  for my $entry (@sub_info) {
    my $grace_end = sql_add_date_days($end, $max_lapsed);
    
    my $order_date = sql_normal_date($entry->{orderDate});
    if ($grace_end ge $order_date) {
      # extend the existing period
      $duration += $entry->{subscription_period};
    }
    else {
      # starting a new period
      $start = $order_date;
      $duration = $entry->{subscription_period};
      push @periods, { start => $start, duration => 0 };
    }
    $max_lapsed = $entry->{max_lapsed};
    $end = sql_add_date_months($start, $duration);
    $periods[-1]{duration} = $duration;
    $periods[-1]{end} = $end;
    $periods[-1]{max_lapsed} = $max_lapsed;
    push @{$periods[-1]{order_ids}}, $entry->{order_id};
    push @{$periods[-1]{product_ids}}, $entry->{product_id};
    push @{$periods[-1]{item_ids}}, $entry->{item_id};
  }

  return @periods;
}

1;
