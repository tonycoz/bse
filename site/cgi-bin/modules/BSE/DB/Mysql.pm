package BSE::DB::Mysql;
use strict;
use DBI;
use vars qw/@ISA/;
@ISA = qw(BSE::DB);

use vars qw($VERSION);

use Constants 0.1 qw/$DSN $UN $PW/;

use Carp;

my $self;

$VERSION = 1.01;

my %statements =
  (
   Articles => 'select * from article',
   replaceArticle =>
     'replace article values (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)',
   addArticle =>  
     'insert article values (null, ?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)',
   deleteArticle => 'delete from article where id = ?',
   getArticleByPkey => 'select * from article where id = ?',
   
   getArticleByLevel => 'select * from article where level = ?',
   getArticleByParentid => 'select * from article where parentid = ?',
   'Articles.stepParents' => <<EOS,
select ar.* from article ar, other_parents op
  where ar.id = op.parentId and op.childId = ?
order by op.childDisplayOrder desc
EOS
   'Articles.stepKids' => <<EOS,
select ar.* from article ar, other_parents op
   where op.childId = ar.id and op.parentId = ?
EOS
   'Articles.visibleStepKids' => <<EOS,
select ar.* from article ar, other_parents op
   where op.childId = ar.id 
     and op.parentId = ? and ? between op.release and op.expire
EOS

   Images => 'select * from image',
   replaceImage =>
     'replace image values (?,?,?,?,?,?,?)',
   addImage => 'insert image values(null, ?, ?, ?, ?, ?, ?)',
   deleteImage => 'delete from image where id = ?',
   getImageByArticleId => 'select * from image where articleId = ?',
   
   dropIndex => 'delete from searchindex',
   insertIndex => 'insert searchindex values(?, ?, ?, ?)',
   searchIndex => 'select * from searchindex where id = ?',
   searchIndexWC => 'select * from searchindex where id like ?',
   
   Products=> 'select article.*, product.* from article, product where id = articleId',
   addProduct => 'insert product values(?,?,?,?,?,?,?)',
   getProductByPkey => 'select article.*, product.* from article, product where id=? and articleId = id',
   replaceProduct => 'replace product values(?,?,?,?,?,?,?)',
   'Products.stepProducts' => <<EOS,
select ar.*, pr.* from article ar, product pr, other_parents op
   where ar.id = pr.articleId and op.childId = ar.id and op.parentId = ?
EOS
   'Products.visibleStep' => <<EOS,
select ar.*, pr.* from article ar, product pr, other_parents op
   where ar.id = pr.articleId and op.childId = ar.id 
     and op.parentId = ? and ? between op.release and op.expire
EOS
   Orders => 'select * from orders',
   getOrderByPkey => 'select * from orders where id = ?',
   getOrderItemByOrderId => 'select * from order_item where orderId = ?',
   addOrder => 'insert orders values(null,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)',
   replaceOrder => 'replace orders values(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)',
   addOrderItem => 'insert order_item values(null,?,?,?,?,?,?,?)',
   getOrderByUserId => 'select * from orders where userId = ?',

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

   addArticleFile =>
   'insert into article_files values (null,?,?,?,?,?,?,?,?,?,?)',
   replaceArticleFile =>
   'replace article_files values (?,?,?,?,?,?,?,?,?,?,?)',
   deleteArticleFile => 'delete from article_files where id = ?',
   getArticleFileByArticleId =>
   'select * from article_files where articleId = ? order by displayOrder desc',
   
   getSiteUserByUserId =>
   'select * from site_users where userId = ?',
   addSiteUser => 'insert site_users values(null,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)',
   replaceSiteUser => 'replace site_users values(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)',
   'SiteUsers.removeSubscriptions'=>
   'delete from subscribed_users where userId = ?',

   SubscriptionTypes =>
   'select * from subscription_types',
   addSubscriptionType=>
   'insert subscription_types values(null,?,?,?,?,?,?,?,?,?,?,?)',
   replaceSubscriptionType=>
   'replace subscription_types values(?,?,?,?,?,?,?,?,?,?,?,?)',
   getSubscriptionTypeByPkey =>
   'select * from subscription_types where id = ? order by name',

   addSubscribedUser=>
   'insert subscribed_users values(null,?,?)',
   getSubscribedUserByUserId =>
   'select * from subscribed_users where userId = ?',

   # the following don't work with the row/table classes
   articlesList =>
   'select id, title from article order by level, displayOrder desc',

   getEmailBlackEntryByEmail =>
   'select * from email_blacklist where email = ?',

   addEmailRequest =>
   'insert email_requests values(null,?,?,?,?)',
   replaceEmailRequest =>
   'replace email_requests values(?,?,?,?,?)',
   getEmailRequestByGenEmail =>
   'select * from email_requests where genEmail = ?',
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

  $name =~ s/BSE:://;

  $statements{$name} or confess "Statement named '$name' not found";
  my $sth = $self->{dbh}->prepare($statements{$name})
    or croak "Cannot prepare $name statment: ",$self->{dbh}->errstr;

  $sth;
}

sub insert_id {
  my ($self, $sth) = @_;

  my $id = $sth->{"mysql_insertid"};

  return $id;
}

# gotta love this
sub DESTROY
{
  my ($self) = @_;
  # this is wierd - we only need to reset this on 5.6.x (for x == 0 so
  # far)
  # Works fine without the reset for 5.005_03
  if ($self->{dbh}) {
    $self->{dbh}->disconnect;
    delete $self->{dbh};
  }
}

1;

