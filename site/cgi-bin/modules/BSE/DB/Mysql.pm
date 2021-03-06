package BSE::DB::Mysql;
use strict;
use DBI;
use vars qw/@ISA/;
use Carp 'confess';
@ISA = qw(BSE::DB);

our $VERSION = "1.014";

use vars qw($MAX_CONNECTION_AGE);

use Carp;

my $self;

$MAX_CONNECTION_AGE = 1200;

my %statements =
  (
   # don't ever load the entire articles table
   #Articles => 'select * from article',
   replaceArticle =>
     'replace article values (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)',
   addArticle =>  
     'insert article values (null, ?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)',
   deleteArticle => 'delete from article where id = ?',
   getArticleByPkey => 'select * from article where id = ?',
   
   getArticleByLevel => 'select * from article where level = ?',
   getArticleByParentid => 'select * from article where parentid = ?',
   getArticleByLinkAlias => 'select * from article where linkAlias = ?',
   'Articles.stepParents' => <<EOS,
select ar.* from article ar, other_parents op
  where ar.id = op.parentId and op.childId = ?
order by op.childDisplayOrder desc
EOS
   'Articles.visibleStepParents' => <<EOS,
select ar.* from article ar, other_parents op
  where ar.id = op.parentId and op.childId = ?
     and date_format(?, '%Y%m%d') between date_format(op.release, '%Y%m%d') and date_format(op.expire, '%Y%m%d')
     and listed <> 0
order by op.childDisplayOrder desc
EOS
   'Articles.stepKids' => <<EOS,
select ar.* from article ar, other_parents op
   where op.childId = ar.id and op.parentId = ?
EOS
# originally "... and ? between op.release and op.expire"
# but since the first argument was a string, mysql treated the comparisons
# as string comparisons
   'Articles.visibleStepKids' => <<EOS,
select ar.* from article ar, other_parents op
   where op.childId = ar.id 
     and op.parentId = ? 
     and date_format(?, '%Y%m%d') between date_format(op.release, '%Y%m%d') and date_format(op.expire, '%Y%m%d') and listed <> 0
EOS
   'Articles.ids'=>'select id from article',
   articlePossibleStepparents => <<EOS,
select a.id, a.title from article a
where a.id not in (select parentId from other_parents where childId = ?) 
      and a.id <> ?;
EOS
   articlePossibleStepchildren => <<EOS,
select a.id, a.title from article a 
where a.id not in (select childId from other_parents where parentId = ?) 
      and a.id <> ?;
EOS
   bse_MaxArticleDisplayOrder => <<EOS,
select max(displayOrder) as "displayOrder" from article
EOS

   Images => 'select * from image',
   replaceImage =>
     'replace image values (?,?,?,?,?,?,?,?,?,?,?,?)',
   addImage => 'insert image values(null, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
   deleteImage => 'delete from image where id = ?',
   getImageByArticleId => 'select * from image where articleId = ? order by displayOrder',
   getImageByPkey => 'select * from image where id = ?',
   getImageByArticleIdAndName => <<SQL,
select * from image where articleId = ? and name = ?
SQL
   
   dropIndex => 'delete from searchindex',
   insertIndex => 'insert searchindex values(?, ?, ?, ?)',
   searchIndex => 'select * from searchindex where id = ?',
   searchIndexWC => 'select * from searchindex where id like ?',
   
   Products=> 'select article.*, product.* from article, product where id = articleId',
   addProduct => 'insert product values(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)',
   getProductByPkey => 'select article.*, product.* from article, product where id=? and articleId = id',
   getProductByProduct_code => 'select article.*, product.* from article, product where product_code=? and articleId = id',
   getProductByLinkAlias => 'select article.*, product.* from article, product where linkAlias=? and articleId = id',
   replaceProduct => 'replace product values(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)',
   'Products.stepProducts' => <<EOS,
select ar.*, pr.* from article ar, product pr, other_parents op
   where ar.id = pr.articleId and op.childId = ar.id and op.parentId = ?
EOS
   'Products.visibleStep' => <<EOS,
select ar.*, pr.* from article ar, product pr, other_parents op
   where ar.id = pr.articleId and op.childId = ar.id 
     and op.parentId = ? and ? between op.release and op.expire
     and listed <> 0
EOS
   'Products.subscriptionDependent' => <<SQL,
select ar.*, pr.* from article ar, product pr
   where ar.id = pr.articleId
     and (pr.subscription_id = ? or subscription_required = ?)
SQL
   'Products.orderProducts' => <<SQL,
select ar.*, pr.* from article ar, product pr, order_item oi
  where oi.orderId = ? and oi.productId = ar.id and ar.id = pr.articleId
SQL
   deleteProduct => 'delete from product where articleId = ?',
   'Products.userWishlist' => <<SQL,
select ar.*, pr.* from article ar, product pr, bse_wishlist wi
  where wi.user_id = ? and wi.product_id = ar.id and ar.id = pr.articleId
order by wi.display_order desc
SQL
   'Products.visible_children_of' => <<SQL,
select ar.*, pr.* from article ar, product pr
   where ar.id = pr.articleId 
     and listed <> 0
     and ar.parentid = ?
     and ? between ar.release and ar.expire
SQL
   bse_userWishlistOrder => <<SQL,
select product_id, display_order
from bse_wishlist
where user_id = ?
order by display_order desc
SQL
   bse_userWishlistReorder => <<SQL,
update bse_wishlist
  set display_order = ?
where user_id = ? and product_id = ?
SQL
   bse_addToWishlist => <<SQL,
insert into bse_wishlist(user_id, product_id, display_order)
  values(?, ?, ?)
SQL
   bse_removeFromWishlist => <<SQL,
delete from bse_wishlist where user_id = ? and product_id = ?
SQL

   Orders => 'select * from orders',
   #getOrderByPkey => 'select * from orders where id = ?',
   getOrderItemByOrderId => 'select * from order_item where orderId = ?',
   #addOrder => 'insert orders values(null,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)',
   #replaceOrder => 'replace orders values(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)',
   #addOrderItem => 'insert order_item values(null,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)',
   #replaceOrderItem => 'replace order_item values(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)',
   #getOrderByUserId => 'select * from orders where userId = ?',
   deleteOrdersItems => 'delete from order_item where orderId = ?',

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

   ArticleFiles => 'select * from article_files',
   addArticleFile =>
   'insert into article_files values (null,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)',
   replaceArticleFile =>
   'replace article_files values (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)',
   deleteArticleFile => 'delete from article_files where id = ?',
   getArticleFileByArticleId =>
   'select * from article_files where articleId = ? order by displayOrder desc',
   getArticleFileByPkey => 'select * from article_files where id = ?',

   "ArticleFiles.orderFiles" =><<SQL,
select distinct af.*
from article_files af, order_item oi
where af.articleId = oi.productId and oi.orderId = ?
order by oi.id, af.displayOrder desc
SQL
   
   # getSiteUserByUserId =>
   # 'select * from site_users where userId = ?',
   # getSiteUserByPkey =>
   # 'select * from site_users where id = ?',
   # getSiteUserByAffiliate_name =>
   # 'select * from site_users where affiliate_name = ?',
   # addSiteUser => 'insert site_users values(null,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)',
   # replaceSiteUser => 'replace site_users values(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)',
   'SiteUsers.removeSubscriptions'=>
   'delete from subscribed_users where userId = ?',
   'SiteUsers.removeSub'=>
   'delete from subscribed_users where userId = ? and subId = ?',
   'SiteUsers.subRecipients' => <<EOS,
select si.* from bse_siteusers si, subscribed_users su
  where confirmed <> 0 and disabled = 0 and si.id = su.userId and su.subId = ?
EOS
   SiteUsers => 'select * from bse_siteusers',
   'SiteUsers.allSubscribers' => <<SQL,
select distinct su.* 
  from bse_siteusers su, orders od, order_item oi
  where su.id = od.siteuser_id and od.id = oi.orderId 
        and oi.subscription_id <> -1
SQL
   siteuserAllIds => 'select id from bse_siteusers',
   getBSESiteuserImage => <<SQL,
select * from bse_siteuser_images
  where siteuser_id = ? and image_id = ?
SQL
   getBSESiteuserImages => <<SQL,
select * from bse_siteuser_images where siteuser_id = ?
SQL
   addBSESiteuserImage => <<SQL,
insert bse_siteuser_images values(?,?,?,?,?,?,?,?)
SQL
   replaceBSESiteuserImage => <<SQL,
replace bse_siteuser_images values(?,?,?,?,?,?,?,?)
SQL
   deleteBSESiteuserImage=> <<SQL,
delete from bse_siteuser_images where siteuser_id = ? and image_id = ?
SQL

   SubscriptionTypes =>
   'select * from subscription_types',
   addSubscriptionType=>
   'insert subscription_types values(null,?,?,?,?,?,?,?,?,?,?,?,?)',
   replaceSubscriptionType=>
   'replace subscription_types values(?,?,?,?,?,?,?,?,?,?,?,?,?)',
   getSubscriptionTypeByPkey =>
   'select * from subscription_types where id = ? order by name',
   deleteSubscriptionType =>
   'delete from subscription_types where id = ?',
   subRecipientCount => <<EOS,
select count(*) as "count" from bse_siteusers si, subscribed_users su
  where confirmed <> 0 and disabled = 0 and si.id = su.userId and su.subId = ?
EOS
   'SubscriptionTypes.userSubscribedTo' => <<'EOS',
select su.* from subscription_types su, subscribed_users us
  where us.userId = ? and us.subId = su.id
EOS

   addSubscribedUser=>
   'insert subscribed_users values(null,?,?)',
   getSubscribedUserByUserId =>
   'select * from subscribed_users where userId = ?',

   # the following don't work with the row/table classes
   articlesList =>
   'select id, title from article order by level, displayOrder desc',

   getEmailBlackEntryByEmail =>
   'select * from email_blacklist where email = ?',
   addEmailBlackEntry =>
   'insert email_blacklist values(null,?,?)',

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
   addAdminUser => 'insert into admin_users values(?,?,?,?,?,?,?)',
   replaceAdminUser => 'replace into admin_users values(?,?,?,?,?,?,?)',
   deleteAdminUser => 'delete from admin_users where base_id = ?',
   "AdminUsers.group_members" => <<SQL,
select bs.*, us.*
  from admin_base bs, admin_users us, admin_membership am
  where bs.id = us.base_id && am.group_id = ? and am.user_id = bs.id
  order by logon
SQL
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
   getAdminGroupByName => <<SQL,
select bs.*, gr.* from admin_base bs, admin_groups gr
  where bs.id = gr.base_id and gr.name = ?
SQL
   getAdminGroupByPkey => <<SQL,
select bs.*, gr.* from admin_base bs, admin_groups gr
  where bs.id = gr.base_id and bs.id = ?
SQL
   addAdminGroup => 'insert into admin_groups values(?,?,?,?,?)',
   replaceAdminGroup => 'replace into admin_groups values(?,?,?,?,?)',
   deleteAdminGroup => 'delete from admin_groups where base_id = ?',
   groupUsers => 'select * from admin_membership where group_id = ?',
   bseAdminGroupMember => <<SQL,
select 1
from admin_membership
where group_id = ?
  and user_id = ?
SQL
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
   Subscriptions => 'select * from bse_subscriptions',
   addSubscription => 'insert bse_subscriptions values(null,?,?,?,?)',
   replaceSubscription => 'replace bse_subscriptions values(?,?,?,?,?)',
   deleteSubscription => <<SQL,
delete from bse_subscriptions where subscription_id = ?
SQL
   getSubscriptionByPkey => <<SQL,
select * from bse_subscriptions where subscription_id = ?
SQL
   getSubscriptionByText_id => <<SQL,
select * from bse_subscriptions where text_id = ?
SQL
   subscriptionOrderItemCount => <<SQL,
select count(*) as "count" from order_item where subscription_id = ?
SQL
   subscriptionOrderSummary => <<SQL,
select od.id, od.userId, od.orderDate, od.siteuser_id, od.billFirstName, od.billLastName, od.filled, 
    sum(oi.subscription_period * oi.units) as "subscription_period"
  from orders od, order_item oi
  where oi.subscription_id = ? and od.id = oi.orderId and od.complete <> 0
  group by od.id, od.userId, od.orderDate, od.siteuser_id
  order by od.orderDate desc
SQL
   subscriptionUserSummary => <<SQL,
select su.*, us.*
  from bse_siteusers su, bse_user_subscribed us
where su.id = us.siteuser_id and us.subscription_id = ?
SQL
   subscriptionProductCount => <<SQL,
select count(*) as "count" from product 
  where subscription_id = ? or subscription_required = ?
SQL
   removeUserSubscribed => <<SQL,
delete from bse_user_subscribed where subscription_id = ? and siteuser_id = ?
SQL
   addUserSubscribed => <<SQL,
insert bse_user_subscribed values (?,?,?,?,?)
SQL
   subscriptionUserBought => <<SQL,
select od.orderDate,
  oi.subscription_period * oi.units as "subscription_period",
  oi.max_lapsed, 
  od.id as "order_id", oi.id as "item_id", oi.productId as "product_id"
  from orders od, order_item oi
  where oi.subscription_id = ? and od.id = oi.orderId and od.siteuser_id = ?
        and od.complete <> 0
SQL
   userSubscribedEntry => <<SQL,
select * from bse_user_subscribed 
  where siteuser_id = ? and subscription_id = ?
SQL
   siteuserSubscriptions => <<SQL,
select su.*, us.started_at, us.ends_at, us.max_lapsed
  from bse_subscriptions su, bse_user_subscribed us
where us.siteuser_id = ? and us.subscription_id = su.subscription_id
   and us.ends_at >= curdate()
SQL

   addLocation => <<SQL,
insert bse_locations values(null,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
SQL
   replaceLocation => <<SQL,
replace bse_locations values(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
SQL
   getLocationByPkey => 'select * from bse_locations where id = ?',
   deleteLocation => 'delete from bse_locations where id = ?',
   Locations => 'select * from bse_locations order by description',

   Seminars => <<SQL,
select ar.*, pr.*, se.*
  from article ar, product pr, bse_seminars se
  where ar.id = pr.articleId and ar.id = se.seminar_id
SQL
   addSeminar => 'insert bse_seminars values(?,?)',
   replaceSeminar => 'replace bse_seminars values(?,?)',
   deleteSeminar => 'delete from bse_seminars where seminar_id = ?',
   getSeminarByPkey => <<SQL,
select ar.*, pr.*, se.*
  from article ar, product pr, bse_seminars se
  where id = ? and ar.id = pr.articleId and ar.id = se.seminar_id
SQL
   getSeminarByProduct_code => <<SQL,
select ar.*, pr.*, se.*
  from article ar, product pr, bse_seminars se
  where product_code = ? and ar.id = pr.articleId and ar.id = se.seminar_id
SQL
   'Locations.seminarFuture' => <<SQL,
select distinct lo.*
  from bse_locations lo, bse_seminar_sessions ss
where ss.seminar_id = ? and ss.when_at > ?
  and ss.location_id = lo.id
order by lo.description
SQL
   'Locations.session_id' => <<SQL,
select lo.*
  from bse_locations lo, bse_seminar_sessions ss
where lo.id = ss.location_id and ss.id = ?
SQL

   seminarSessionInfo => <<SQL,
select se.*, lo.description
  from bse_seminar_sessions se, bse_locations lo
  where se.seminar_id = ? and se.location_id = lo.id
order by when_at desc
SQL
   seminarFutureSessionInfo => <<SQL,
select se.*, lo.description, lo.room, lo.street1, lo.street2, lo.suburb, 
    lo.state, lo.country, lo.postcode, lo.public_notes
  from bse_seminar_sessions se, bse_locations lo
  where se.seminar_id = ? and se.when_at > ? and se.location_id = lo.id
order by when_at desc
SQL
   addSeminarSession => 'insert bse_seminar_sessions values(null,?,?,?,?)',
   replaceSeminarSession => 'replace bse_seminar_sessions values(?,?,?,?,?)',
   deleteSeminarSession => 'delete from bse_seminar_sessions where id = ?',
   getSeminarSessionByPkey => 'select * from bse_seminar_sessions where id = ?',
   getSeminarSessionByLocation_idAndWhen_at => <<SQL,
select * from bse_seminar_sessions
  where location_id = ? and when_at = ?
SQL
   getSeminarSessionBySeminar_id => <<SQL,
select * from bse_seminar_sessions
  where seminar_id = ?
SQL
   'SeminarSessions.futureSessions' => <<SQL,
select * from bse_seminar_sessions
  where seminar_id = ? and when_at >= ?
SQL
   'SeminarSessions.futureSeminarLocation' => <<SQL,
select *
  from bse_seminar_sessions
  where seminar_id = ? and location_id = ? and when_at > ?
SQL
   'SiteUsers.sessionBookings' => <<SQL,
select su.* from bse_siteusers su, bse_seminar_bookings sb
  where sb.session_id = ? and su.id = sb.siteuser_id
SQL
   cancelSeminarSessionBookings => <<SQL,
delete from bse_seminar_bookings where session_id = ?
SQL
   conflictSeminarSessions => <<SQL,
select bo1.siteuser_id
  from bse_seminar_bookings bo1, bse_seminar_bookings bo2
where bo1.session_id = ? and bo2.session_id = ? 
  and bo1.siteuser_id = bo2.siteuser_id
SQL
   seminarSessionBookedIds => <<SQL,
select * from bse_seminar_bookings where session_id = ?
SQL
   addSeminarBooking => <<SQL,
insert bse_seminar_bookings values(null,?,?,?,?,?,?)
SQL
   seminarSessionRollCallEntries => <<SQL,
select bo.roll_present, su.id, su.userId, su.name1, su.name2, su.email,
    bo.id as booking_id
  from bse_seminar_bookings bo, bse_siteusers su
where bo.session_id = ? and bo.siteuser_id = su.id
SQL
  updateSessionRollPresent => <<SQL,
update bse_seminar_bookings
  set roll_present = ?
  where session_id = ? and siteuser_id = ?
SQL
   userSeminarSessionBookings => <<SQL,
select session_id 
  from bse_seminar_bookings sb, bse_seminar_sessions ss
where ss.seminar_id = ? and ss.id = sb.session_id and siteuser_id = ?
SQL
   SiteUserGroups => 'select * from bse_siteuser_groups',
   addSiteUserGroup => 'insert bse_siteuser_groups values(null,?)',
   replaceSiteUserGroup => 'replace bse_siteuser_groups values(?,?)',
   deleteSiteUserGroup => 'delete from bse_siteuser_groups where id = ?',
   getSiteUserGroupByPkey => 'select * from bse_siteuser_groups where id = ?',
   getSiteUserGroupByName => 'select * from bse_siteuser_groups where name = ?',
   siteuserGroupMemberIds => <<SQL,
select siteuser_id as "id" 
from bse_siteuser_membership 
where group_id = ?
SQL
   siteuserGroupAddMember => <<SQL,
insert bse_siteuser_membership values(?,?)
SQL
   siteuserGroupDeleteMember => <<SQL,
delete from bse_siteuser_membership where group_id = ? and siteuser_id = ?
SQL
    siteuserGroupDeleteAllMembers => <<SQL,
delete from bse_siteuser_membership where group_id = ?
SQL
    siteuserMemberOfGroup => <<SQL,
select * from bse_siteuser_membership 
where siteuser_id = ? and group_id = ?
SQL
    siteuserGroupsForUser => <<SQL,
select group_id as "id" from bse_siteuser_membership where siteuser_id = ?
SQL

    articleAccessibleToGroup => <<SQL,
select * from bse_article_groups
where article_id = ? and group_id = ?
SQL
    siteuserGroupsForArticle => <<SQL,
select group_id as "id" from bse_article_groups
where article_id = ?
SQL
    articleAddSiteUserGroup => <<SQL,
insert bse_article_groups values(?,?)
SQL
    articleDeleteSiteUserGroup => <<SQL,
delete from bse_article_groups 
where article_id = ? and group_id = ?
SQL
    siteuserGroupDeleteAllPermissions => <<SQL,
delete from bse_article_groups where group_id = ?
SQL
  );

# called when we start working on a new request, mysql seems to have
# problems with old connections sometimes, or so it seems, so
# disconnect occasionally (only matters for fastcgi, mod_perl)
sub _startup {
  my $class = shift;

  if ($self) {
    unless ($self->{dbh}->ping) {
      print STDERR "Database connection lost - reconnecting\n";
      $self->{dbh} = $class->connect;
      $self->{birth} = time();
    }
  }
}

sub connect {
  my ($class, $dbname) = @_;

  my $dsn = $class->dsn($dbname);
  my $un = $self->dbuser($dbname);
  my $pass = $self->dbpassword($dbname);
  my $dbopts = $self->dbopts($dbname);
  my $dbh = DBI->connect( $dsn, $un, $pass, $dbopts)
      or die "Cannot connect to database: $DBI::errstr";

  # this might fail, but I don't care
  $dbh->do("set session sql_mode='ansi_quotes'");

  return $dbh;
}

sub _single
{
  my ($class, $cfg) = @_;

  warn "Incorrect number of parameters passed to BSE::DB::Mysql::single\n" unless @_ == 2;
  
  unless ( defined $self ) {
    $self = bless 
      { 
       dbh => undef,
       birth => time(),
       cfg => $cfg,
      }, $class;

    $self->{dbh} = $self->connect;
  }
  $self;
}

sub _forked {
  my $self = shift;

  $self->{dbh}{InactiveDestroy} = 1;
  delete $self->{dbh};
  $self->{dbh} = $self->connect;
}


my $get_sql_by_name = 'select sql_statement from sql_statements where name=?';

my %sql_cache;

sub stmt_sql {
  my ($self, $name) = @_;

  $name =~ s/BSE.*:://;

  my $sql = $statements{$name};
  unless ($sql) {
    if (exists $sql_cache{$name}) {
      return $sql_cache{$name};
    }
  }
  unless ($sql) {
    my @row = $self->{dbh}->selectrow_array($get_sql_by_name, {}, $name);
    if (@row) {
      $sql = $row[0];
      #print STDERR "Found SQL '$sql'\n";
    }
    else {
      #print STDERR "SQL statment $name not found in sql_statements table\n";
    }

    $sql_cache{$name} = $sql;
  }

  return $sql;
}

sub stmt {
  my ($self, $name) = @_;

  my $sql = $self->stmt_sql($name)
    or confess "Statement named '$name' not found";
  my $sth = $self->{dbh}->prepare($sql)
    or croak "Cannot prepare $name statment: ",$self->{dbh}->errstr;

  $sth;
}

sub stmt_noerror {
  my ($self, $name) = @_;

  my $sql = $self->stmt_sql($name)
    or return;
  my $sth = $self->{dbh}->prepare($sql)
    or croak "Cannot prepare $name statment: ",$self->{dbh}->errstr;

  $sth;
}

sub insert_id {
  my ($self, $sth) = @_;

  my $id = $sth->{"mysql_insertid"};

  return $id;
}

sub dbopts {
  my ($class) = @_;

  my $opts = $class->SUPER::dbopts();

  if (BSE::Cfg->utf8
      && lc(BSE::Cfg->charset) eq "utf-8") {
    $opts->{mysql_enable_utf8} = 1;
  }

  return $opts;
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

