package BSE::DB::Mysql;

use DBI;

use vars qw($VERSION);

use Constants 0.1 qw/$DSN $UN $PW/;

use Carp;

$VERSION = 1.01;

my %statements =
  (
   Articles => 'select * from article',
   Images => 'select * from image',
   
   replaceArticle =>
     'replace article values (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)',
   replaceImage =>
     'replace image values (?,?,?,?,?,?,?)',
   
   addArticle =>  
     'insert article values (null, ?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)',
   addImage => 'insert image values(null, ?, ?, ?, ?, ?, ?)',
   
   deleteArticle => 'delete from article where id = ?',
   deleteImage => 'delete from image where id = ?',
   
   getImageByArticleId => 'select * from image where articleId = ?',
   
   getArticleByPkey => 'select * from article where id = ?',
   
   getArticleByLevel => 'select * from article where level = ?',
   getArticleByParentid => 'select * from article where parentid = ?',
   dropIndex => 'delete from searchindex',
   insertIndex => 'insert searchindex values(?, ?, ?, ?)',
   searchIndex => 'select * from searchindex where id = ?',
   searchIndexWC => 'select * from searchindex where id like ?',
   
   Products=> 'select article.*, product.* from article, product where id = articleId',
   addProduct => 'insert product values(?,?,?,?,?,?,?)',
   getProductByPkey => 'select article.*, product.* from article, product where id=? and articleId = id',
   replaceProduct => 'replace product values(?,?,?,?,?,?,?)',
   
   Orders => 'select * from orders',
   getOrderByPkey => 'select * from orders where id = ?',
   getOrderItemByOrderId => 'select * from order_item where orderId = ?',
   addOrder => 'insert orders values(null,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)',
   replaceOrder => 'replace orders values(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)',
   addOrderItem => 'insert order_item values(null,?,?,?,?,?,?,?)',
  );

sub _single
{
  my $class = shift;
  warn "Incorrect number of parameters passed to DatabaseHandle::single\n" unless @_ == 0;
  
  unless ( defined $self ) {
    my $dbh = DBI->connect_cached( $DSN, $UN, $PW)
      or die "Cannot connect to database: $DBI::errstr";
    
    $self = bless { dbh => $dbh }, $class;
  }
  $self;
}

sub stmt {
  my ($self, $name) = @_;

  $statements{$name} or croak "Statement named '$name' not found";
  my $sth = $self->{dbh}->prepare($statements{$name})
    or croak "Cannot prepare $name statment: ",$self->{dbh}->errstr;

  $sth;
}

sub insert_id {
  my ($self, $sth) = @_;

  return $self->{dbh}->{'mysql_insertid'};
}

# gotta love this
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

