package BSE::DB::MSSQL;
use strict;
use DBI;

our $VERSION = "1.000";

use vars qw($VERSION);

use Constants 0.1 qw/$DSN $DBOPTS $UN $PW/;

use Carp;

$VERSION = 1.00;

my %statements =
  (
   Articles => 'exec bse_get_articles',
   Images => 'exec bse_get_images',
   
   replaceArticle =>
     'exec bse_update_article ?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?',
   replaceImage =>
     'exec bse_update_image ?,?,?,?,?,?',
   
   addArticle =>  
     'exec bse_add_article ?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?',
   addImage => 'exec bse_add_image ?, ?, ?, ?, ?',
   
   deleteArticle => 'exec bse_delete_article ?',
   deleteImage => 'exec bse_delete_image ?',
   
   getImageByArticleId => 'exec bse_get_article_images ?',
   
   getArticleByPkey => 'exec bse_get_an_article ?',
   
   getArticleByLevel => 'exec bse_articles_by_level ?',
   getArticleByParentid => 'exec bse_articles_by_parent ?',
   dropIndex => 'exec bse_clear_search_index',
   insertIndex => 'exec bse_add_searchindex ?, ?, ?, ?',
   searchIndex => 'exec bse_search ?',
   searchIndexWC => 'exec bse_search_wc ?',
   
   Products=> 'exec bse_get_products',
   addProduct => 'exec bse_add_product ?,?,?,?,?,?,?',
   getProductByPkey => 'exec bse_get_a_product ?',
   replaceProduct => 'exec bse_update_product ?,?,?,?,?,?,?',
   
   Orders => 'exec bse_get_orders',
   getOrderByPkey => 'exec bse_get_an_order ?',
   getOrderItemByOrderId => 'exec bse_order_items_by_order ?',
   addOrder => 'exec bse_add_order ?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?',
   replaceOrder => 'exec bse_update_order ?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?',
   addOrderItem => 'exec bse_add_order_item ?,?,?,?,?,?,?',

   OtherParents => 'select * from other_parents',
   getOtherParentByChildId => <<EOS,
select * from other_parents where childId = ? order by childDisplayOrder desc
EOS
   getOtherParentByParentId => <<EOS,
select * from other_parents where parentId = ? order by parentDisplayOrder desc
EOS
   getOtherParentByParentIdAndChildId =>
   'select * from other_parents where parentId = ? and childId = ?',
   addOtherParent=>'insert other_parents values(null,?,?,?,?,?,?)',
   deleteOtherParent => 'delete from other_parents where id = ?',
   replaceOtherParent=>'replace other_parents values(?,?,?,?,?,?,?)',
   'OtherParents.anylinks' => 
   'select * from other_parents where childId = ? or parentId = ?',
   
   identity => 'select @@identity',
  );

sub _single
{
  my $class = shift;

  warn "Incorrect number of parameters passed to BSE::DB::MYSQL::_single\n" 
    unless @_ == 0;
  
  unless ( defined $self ) {
    my $dbh = DBI->connect_cached($DSN, $UN, $PW, $DBOPTS)
      or die "Cannot connect to database: $DBI::errstr";
    
    $self = bless { dbh => $dbh }, $class;
  }
  $self;
}

sub stmt {
  my ($self, $name) = @_;

  $statements{$name} or croak "Statement named '$name' not found";
  if ($self->{stmts}{$name}) {
    return $self->{stmts}{$name};
  }
  else {
    my $sth = $self->{dbh}->prepare($statements{$name})
      or croak "Cannot prepare $name statment: ",$self->{dbh}->errstr;
    
    return $sth;
  }
}

sub insert_id {
  my ($self, $sth) = @_;

  my $sth2 = $self->stmt('identity');
  $sth2->execute() or die "Cannot get identity",$sth2->errstr,"\n";
  my @row = $sth2->fetchrow_array();
  @row or die "Cannot fetch identity\n";
  $sth2->finish;

  return $row[0];
}

sub DESTROY
{
  # this is wierd - we only need to reset this on 5.6.x (for x == 0 so
  # far)
  # Works fine without the reset for 5.005_03
  if ($dbh) {
    $dbh->disconnect;
    undef $dbh;
  }
}

1;

