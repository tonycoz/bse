package BSE::SubscriptionType;
use strict;
# represents a subscription type from the database
use Squirrel::Row;
use vars qw/@ISA/;
@ISA = qw/Squirrel::Row/;

sub columns {
  return qw/id name title description frequency keyword archive 
            article_template html_template text_template parentId lastSent/;
}

1;
