#!perl -w
use strict;
use Test::More tests=>9;

my $gotmodule = require_ok('BSE::TB::Subscription::Calc');

SKIP: {
  skip "couldn't load module", 9 unless $gotmodule;

  # simple as it gets
  my @result = BSE::TB::Subscription::Calc->calculate_period
    (1,
     { 
      orderDate => '2004/02/04 10:00', # seconds should get stripped in code
      subscription_period=>1,
      order_id => 1,
      product_id => 3,
      item_id => 2,
      max_lapsed => 0,
     }
    );
  is(@result, 1, "simple, correct period count");
  is_deeply(\@result,
	    [
	     { start => '2004-02-04',
	       end => '2004-03-04',
	       duration => 1,
	       order_ids => [ 1 ],
	       product_ids => [ 3 ],
	       item_ids => [ 2 ],
	       max_lapsed => 0,
	     },
	    ], "simple, correct period");

  # overlapping ranges
  @result = BSE::TB::Subscription::Calc->calculate_period
    (1,
     { 
      orderDate => '2004/02/04', # seconds should get stripped in code
      subscription_period=>1,
      order_id => 1,
      product_id => 3,
      item_id => 2,
      max_lapsed => 0,
     },
     {
      orderDate => '2004/02/28', # seconds should get stripped in code
      subscription_period=>1,
      order_id => 2,
      product_id => 3,
      item_id => 4,
      max_lapsed => 0,
     },
    );
  is(@result, 1, "connected, correct period count");
  is_deeply(\@result,
	    [
	     { start => '2004-02-04',
	       end => '2004-04-04',
	       duration => 2,
	       order_ids => [ 1, 2 ],
	       product_ids => [ 3, 3 ],
	       item_ids => [ 2, 4 ],
	       max_lapsed => 0,
	     },
	    ], "connected, correct period");

  # completely disconnected ranges
  @result = BSE::TB::Subscription::Calc->calculate_period
    (1,
     { 
      orderDate => '2004/02/04', # seconds should get stripped in code
      subscription_period=>1,
      order_id => 1,
      product_id => 3,
      item_id => 2,
      max_lapsed => 0,
     },
     {
      orderDate => '2004/03/05', # seconds should get stripped in code
      subscription_period=>1,
      order_id => 2,
      product_id => 3,
      item_id => 4,
      max_lapsed => 0,
     },
    );
  is(@result, 2, "disconnected, correct period count");
  is_deeply(\@result,
	    [
	     { start => '2004-02-04',
	       end => '2004-03-04',
	       duration => 1,
	       order_ids => [ 1 ],
	       product_ids => [ 3 ],
	       item_ids => [ 2 ],
	       max_lapsed => 0,
	     },
	     { start => '2004-03-05',
	       end => '2004-04-05',
	       duration => 1,
	       order_ids => [ 2 ],
	       product_ids => [ 3 ],
	       item_ids => [ 4 ],
	       max_lapsed => 0,
	     },
	    ], "disconnected, correct period");

  # connected by grace period
  @result = BSE::TB::Subscription::Calc->calculate_period
    (1,
     { 
      orderDate => '2004/02/04', # seconds should get stripped in code
      subscription_period=>1,
      order_id => 1,
      product_id => 3,
      item_id => 2,
      max_lapsed => 1,
     },
     {
      orderDate => '2004/03/05', # seconds should get stripped in code
      subscription_period=>1,
      order_id => 2,
      product_id => 3,
      item_id => 4,
      max_lapsed => 2,
     },
    );

  is(@result, 1, "grace period, correct period count");
  is_deeply(\@result,
	    [
	     { start => '2004-02-04',
	       end => '2004-04-04',
	       duration => 2,
	       order_ids => [ 1, 2 ],
	       product_ids => [ 3, 3 ],
	       item_ids => [ 2, 4 ],
	       max_lapsed => 2,
	     },
	    ], "grace period, correct period");
}
