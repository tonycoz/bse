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
   'Articles.ids'=>'select id from article',

   Images => 'select * from image',
   replaceImage =>
     'replace image values (?,?,?,?,?,?,?,?)',
   addImage => 'insert image values(null, ?, ?, ?, ?, ?, ?, ?)',
   deleteImage => 'delete from image where id = ?',
   getImageByArticleId => 'select * from image where articleId = ? order by displayOrder',
   
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
   deleteProduct => 'delete from product where articleId = ?',
   Orders => 'select * from orders',
   getOrderByPkey => 'select * from orders where id = ?',
   getOrderItemByOrderId => 'select * from order_item where orderId = ?',
   addOrder => 'insert orders values(null,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)',
   replaceOrder => 'replace orders values(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)',
   addOrderItem => 'insert order_item values(null,?,?,?,?,?,?,?)',
   getOrderByUserId => 'select * from orders where userId = ?',

   getOrderItemByProductId => 'select * from order_item where productId = ?',

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
   'insert into article_files values (null,?,?,?,?,?,?,?,?,?,?,?)',
   replaceArticleFile =>
   'replace article_files values (?,?,?,?,?,?,?,?,?,?,?,?)',
   deleteArticleFile => 'delete from article_files where id = ?',
   getArticleFileByArticleId =>
   'select * from article_files where articleId = ? order by displayOrder desc',
   getArticleFileByPkey => 'select * from article_files where id = ?',

   orderFiles =><<SQL,
select distinct af.*, oi.id as item_id
from article_files af, order_item oi
where af.articleId = oi.productId and oi.orderId = ?
order by af.description
SQL
   
   getSiteUserByUserId =>
   'select * from site_users where userId = ?',
   getSiteUserByPkey =>
   'select * from site_users where id = ?',
   addSiteUser => 'insert site_users values(null,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)',
   replaceSiteUser => 'replace site_users values(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)',
   'SiteUsers.removeSubscriptions'=>
   'delete from subscribed_users where userId = ?',
   'SiteUsers.removeSub'=>
   'delete from subscribed_users where userId = ? and subId = ?',
   'SiteUsers.subRecipients' => <<EOS,
select si.* from site_users si, subscribed_users su
  where confirmed <> 0 and si.id = su.userId and su.subId = ?
EOS

   SubscriptionTypes =>
   'select * from subscription_types',
   addSubscriptionType=>
   'insert subscription_types values(null,?,?,?,?,?,?,?,?,?,?,?,?)',
   replaceSubscriptionType=>
   'replace subscription_types values(?,?,?,?,?,?,?,?,?,?,?,?,?)',
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
   deleteEmailRequest =>
   'delete from email_requests where id = ?',
   getEmailRequestByGenEmail =>
   'select * from email_requests where genEmail = ?',

   addAdminBase => 'insert into admin_base values(null, ?)',
   replaceAdminBase => 'replace into admin_base values(?, ?)',
   deleteAdminBase => 'delete from admin_base where id = ?',
   getAdminBaseByPkey => 'select * from admin_base where id=?',
   
   AdminUsers => <<SQL,
select bs.*, us.* from admin_base bs, admin_users us
  where bs.id = us.base_id
   order by logon
SQL
   getAdminUserByLogon => <<SQL,
select bs.*, us.* from admin_base bs, admin_users us
  where bs.id = us.base_id and us.logon = ?
SQL
   getAdminUserByPkey => <<SQL,
select bs.*, us.* from admin_base bs, admin_users us
  where bs.id = us.base_id and bs.id = ?
SQL
   addAdminUser => 'insert into admin_users values(?,?,?,?,?)',
   replaceAdminUser => 'replace into admin_users values(?,?,?,?,?)',
   deleteAdminUser => 'delete from admin_users where base_id = ?',
   adminUsersGroups => <<SQL,
select bs.*, gr.*
  from admin_base bs, admin_groups gr, admin_membership am
  where bs.id = gr.base_id && am.user_id = ? and am.group_id = bs.id
  order by gr.name
SQL
   userGroups => 'select * from admin_membership where user_id = ?',
   deleteUserGroups => 'delete from admin_membership where user_id = ?',

   AdminGroups => <<SQL,
select bs.*, gr.* 
  from admin_base bs, admin_groups gr
  where bs.id = gr.base_id
  order by name
SQL
   adminGroupsUsers => <<SQL,
select bs.*, us.*
  from admin_base bs, admin_users us, admin_membership am
  where bs.id = us.base_id && am.group_id = ? and am.user_id = bs.id
  order by logon
SQL
   getAdminGroupByName => <<SQL,
select bs.*, gr.* from admin_base bs, admin_groups gr
  where bs.id = gr.base_id and gr.name = ?
SQL
   getAdminGroupByPkey => <<SQL,
select bs.*, gr.* from admin_base bs, admin_groups gr
  where bs.id = gr.base_id and bs.id = ?
SQL
   addAdminGroup => 'insert into admin_groups values(?,?,?,?)',
   replaceAdminGroup => 'replace into admin_groups values(?,?,?,?)',
   deleteAdminGroup => 'delete from admin_groups where base_id = ?',
   groupUsers => 'select * from admin_membership where group_id = ?',
   'AdminGroups.userPermissionGroups' => <<SQL,
select bs.*, ag.* from admin_base bs, admin_groups ag, admin_membership am
where bs.id = ag.base_id
  and ( (ag.base_id = am.group_id and am.user_id = ?) 
        or ag.name = 'everyone' )
SQL

   addUserToGroup => 'insert into admin_membership values(?,?)',
   delUserFromGroup => <<SQL,
delete from admin_membership where user_id = ? and group_id = ?
SQL
   deleteGroupUsers => 'delete from admin_membership where group_id = ?',

   articleObjectPerm => <<SQL,
select * from admin_perms where object_id = ? and admin_id = ?
SQL
   addArticleObjectPerm => 'insert into admin_perms values(?,?,?)',
   replaceArticleObjectPerm => 'replace into admin_perms values(?,?,?)',
   userPerms => <<SQL,
select distinct ap.* 
from admin_perms ap
where ap.admin_id = ?
SQL
   groupPerms => <<SQL,
select distinct ap.* 
from admin_perms ap, admin_membership am
where ap.admin_id = am.group_id and am.user_id = ?
SQL
   commonPerms => <<SQL,
select distinct ap.* 
from admin_perms ap, admin_groups ag
where ap.admin_id = ag.base_id and ag.name = 'everyone'
SQL
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

  $name =~ s/BSE.*:://;

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

