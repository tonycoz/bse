package Product;
use strict;
# represents a product from the database
use Article;
use vars qw/@ISA/;
@ISA = qw/Article/;

sub columns {
  return ($_[0]->SUPER::columns(), 
	  qw/articleId summary leadTime retailPrice wholesalePrice gst options/ );
}

sub bases {
  return { articleId=>{ class=>'Article'} };
}

1;
