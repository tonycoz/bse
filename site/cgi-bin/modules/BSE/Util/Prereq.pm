package BSE::Util::Prereq;
use strict;

our $VERSION = "1.000";

# pre-requisites for various modules

our %prereqs =
  (
   "BSE::Cache::Memcached" => [ "Cache::Memcached::Fast" ],
  );
