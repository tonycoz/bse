-- represents sections, articles
DROP TABLE IF EXISTS article;
CREATE TABLE article (
  id integer NOT NULL auto_increment,

  -- 0 for the entry page
  -- -1 for top-level sections (shown in side menu)
  parentid integer DEFAULT '0' NOT NULL,

  -- the order to display articles in
  -- used for ordering sibling articles
  displayOrder integer not NULL default 0,
  title varchar(255) DEFAULT '' NOT NULL,
  titleImage varchar(64) not null,
  body text NOT NULL,

  -- thumbnail image
  thumbImage varchar(64) not null default '',
  thumbWidth integer not null,
  thumbHeight integer not null,

  -- position of first image for this article
  imagePos char(2) not null,
  release datetime DEFAULT '0000-00-00 00:00:00' NOT NULL,
  expire datetime DEFAULT '9999-12-31 23:59:59' NOT NULL,
  keyword varchar(255) not null default '',

  -- the template in $TMPLDIR used to generate this as HTML
  template varchar(127) DEFAULT '' NOT NULL,

  -- a link to the page generated for this article
  -- if this is blank then no page is generated
  -- this is combined with the base of the site to get the file
  -- written to during generation
  link varchar(64) not null,
  admin varchar(64) not null,

  -- if there are more child articles than this, display links/summaries
  -- if the same of fewer, embed the articles
  -- the template can ignore this
  threshold integer not null default 3,

  -- the length of summary to display for this article
  summaryLength smallint(5) unsigned DEFAULT '200' NOT NULL,

  -- the class whose generate() method generates the page
  generator varchar(40) not null default 'article',

  -- the level of the article, 1 for top-level
  level smallint not null,

  -- for listed:
  -- 0 - don't list
  -- 1 - list everywhere
  -- 2 - list in sections, but not on the menu
  listed smallint not null default 1,
  -- date last modified
  lastModified datetime not null,

  -- flags specified via the config file
  -- used by code and templates
  flags varchar(80) not null default '',

  -- custom fields for local usage
  customDate1 datetime null,
  customDate2 datetime null,

  customStr1 varchar(255) null,
  customStr2 varchar(255) null,

  customInt1 integer null,
  customInt2 integer null,
  customInt3 integer null,
  customInt4 integer null,

  -- added by adrian
  lastModifiedBy varchar(60) default '' not null,
  created datetime default '0000-00-00 00:00:00' not null,
  createdBy varchar(60) default '' not null,
  author varchar(255) default '' not null,
  pageTitle varchar(255) default '' not null,

  PRIMARY KEY (id),

  -- if we keep id in the indexes MySQL will sometimes be able to
  -- perform a query using _just_ the index, without scanning through
  -- all our main records with their blobs
  -- Unfortunately MySQL can only do this on fixed-width columns
  -- other databases may not need the id in the index, and may also be
  -- able to handle the variable length columns in the index
  INDEX article_date_index (release,expire, id),
  INDEX article_displayOrder_index (displayOrder),
  INDEX article_parentId_index (parentId),
  INDEX article_level_index (level, id)
);

#
# Table structure for table 'searchindex'
#

DROP TABLE IF EXISTS searchindex;
CREATE TABLE searchindex (
  id varbinary(200) DEFAULT '' NOT NULL,
  -- a comma-separated lists of article and section ids
  articleIds varchar(255) default '' not null,
  sectionIds varchar(255) default '' not null,
  scores varchar(255) default '' not null,
  PRIMARY KEY (id)
);

#
# Table structure for table 'image'
#
DROP TABLE IF EXISTS image;
CREATE TABLE image (
  id mediumint(8) unsigned NOT NULL auto_increment,
  articleId integer not null,
  image varchar(64) DEFAULT '' NOT NULL,
  alt varchar(255) DEFAULT '[Image]' NOT NULL,
  width smallint(5) unsigned,
  height smallint(5) unsigned,
  url varchar(255),
  displayOrder integer not null default 0,
  name varchar(255) default '' not null,

  PRIMARY KEY (id)
);

# used for session tracking with Apache::Session::MySQL
DROP TABLE IF EXISTS sessions;
CREATE TABLE sessions (
  id char(32) not null primary key,
  a_session text,
  -- so we can age this table
  whenChanged timestamp
);

-- these share data with the article table
DROP TABLE IF EXISTS product;
create table product (
  -- fkey to article id
  articleId integer not null,

  summary varchar(255) not null,

  -- number of days it typically takes to supply this item
  leadTime integer not null default 0,

  -- prices are in cents
  retailPrice integer not null,
  wholesalePrice integer,

  -- amount of GST on this item
  gst integer not null,

  -- options that can be specified for this product
  options varchar(255) not null,

  subscription_id integer not null default -1,
  subscription_period integer not null default 0,
  subscription_usage integer not null default 3,
  subscription_required integer not null default -1,
  
  primary key(articleId)
);

-- order is a reserved word
-- I couldn't think of/find another word here
DROP TABLE IF EXISTS orders;
create table orders (
  id integer not null auto_increment,

  -- delivery address
  delivFirstName varchar(127) not null default '',
  delivLastName varchar(127) not null default '',
  delivStreet varchar(127) not null default '',
  delivSuburb varchar(127) not null default '',
  delivState varchar(40) not null default '',
  delivPostCode varchar(40) not null default '',
  delivCountry varchar(127) not null default 'Australia',

  -- billing address
  billFirstName varchar(127) not null default '',
  billLastName varchar(127) not null default '',
  billStreet varchar(127) not null default '',
  billSuburb varchar(127) not null default '',
  billState varchar(40) not null default '',
  billPostCode varchar(40) not null default '',
  billCountry varchar(127) not null default 'Australia',

  telephone varchar(80) not null default '',
  facsimile varchar(80) not null default '',
  emailAddress varchar(255) not null default '',
  
  -- total price
  total integer not null,	
  wholesaleTotal integer not null default 0,
  gst integer not null,
  
  orderDate datetime not null,
  
  -- credit card information
  ccNumberHash varchar(127) not null default '',
  ccName varchar(127) not null default '',
  ccExpiryHash varchar(127) not null default '',
  ccType varchar(30) not null,

  -- non-zero if the order was filled
  filled integer not null default 0,
  whenFilled datetime,
  whoFilled varchar(40) not null default '',

  -- if the order has been paid for
  paidFor integer not null default 0,
  paymentReceipt varchar(40),

  -- hard to guess identifier
  randomId varchar(40),

  -- order was cancelled
  cancelled integer not null default 0,

  -- user id of the person who made the order
  -- an empty string if there's no user
  userId varchar(40) not null,

  paymentType integer not null default 0,

  -- intended for custom uses
  customInt1 integer null,
  customInt2 integer null,
  customInt3 integer null,
  customInt4 integer null,
  customInt5 integer null,

  customStr1 varchar(255) null,
  customStr2 varchar(255) null,
  customStr3 varchar(255) null,
  customStr4 varchar(255) null,
  customStr5 varchar(255) null,

  instructions text not null default '',
  billTelephone varchar(80) not null default '',
  billFacsimile varchar(80) not null default '',
  billEmail varchar(255) not null default '',

  siteuser_id integer,
  affiliate_code varchar(40) not null default '',

  shipping_cost integer not null default 0,

  delivMobile varchar(80) not null default '',
  billMobile varchar(80) not null default '',

  -- information from online credit card processing
  -- non-zero if we did online CC processing
  ccOnline integer not null default 0,
  -- non-zero if processing was successful
  ccSuccess integer not null default 0,
  -- receipt number
  ccReceipt varchar(80) not null default '',
  -- main status code (value depends on driver)
  ccStatus integer not null default 0,
  ccStatusText varchar(80) not null default '',
  -- secondary status code (if any)
  ccStatus2 integer not null default 0,
  -- card processor transaction identifier
  -- the ORDER_NUMBER for Inpho
  ccTranId varchar(40) not null default '',

  -- order was completed by the customer
  complete integer not null default 1,

  delivOrganization varchar(127) not null default '',
  billOrganization varchar(127) not null default '',

  delivStreet2 varchar(127) not null default '',
  billStreet2 varchar(127) not null default '',

  primary key (id),
  index order_cchash(ccNumberHash),
  index order_userId(userId, orderDate)
);

DROP TABLE IF EXISTS order_item;
create table order_item (
  id integer not null auto_increment,
  -- foreign key to product
  productId integer not null,

  -- foreign key to order
  orderId integer not null,
  
  -- how many :)
  units integer not null,

  -- unit prices
  price integer not null,
  wholesalePrice integer not null,
  gst integer not null,

  -- options (if any) specified on this item in the order
  options varchar(255) not null,

  customInt1 integer null,
  customInt2 integer null,
  customInt3 integer null,

  customStr1 varchar(255) null,
  customStr2 varchar(255) null,
  customStr3 varchar(255) null,

  -- transferred from the product
  title varchar(255) not null default '',
  summary varchar(255) not null default '',
  subscription_id integer not null default -1,
  subscription_period integer not null default 0,

  -- transferred from the subscription
  max_lapsed integer not null default 0,

  -- session for a seminar
  session_id integer not null default -1,

  primary key (id),
  index order_item_order(orderId, id)
);

drop table if exists other_parents;
create table other_parents (
  id integer not null auto_increment,

  parentId integer not null,
  childId integer not null,

  -- order as seen from the parent
  parentDisplayOrder integer not null,
  -- order as seen from the child
  childDisplayOrder integer not null,

  release datetime default '0000-00-00 00:00:00' not null,
  expire datetime default '9999-12-31 23:59:59' not null,

  primary key(id),
  unique (parentId, childId),
  index (childId, childDisplayOrder)
);

-- initially we just do paid for files, later we may add unpaid for files
-- there's some database support here to support unpaid for files
-- but it won't be implemented yet
drop table if exists article_files;
create table article_files (
  id integer not null auto_increment,
  articleId integer not null,

  -- the name of the file as displayed
  displayName varchar(80) not null default '',

  -- the filename as stored in the repository
  filename varchar(80) not null default '',

  -- how big it is
  sizeInBytes integer not null,

  -- a description of the file
  description varchar(255) not null default '',

  -- content type
  contentType varchar(80) not null default 'application/octet-stream',

  -- used to control the order the files are displayed in
  displayOrder integer not null,

  -- if non-zero this item is for sale
  -- it has no public URL and can only be downloaded via a script
  forSale integer not null default 0,

  -- we try to make the browser download the file rather than display it
  download integer not null default 0,

  -- when it was uploaded
  whenUploaded datetime not null,

  -- user must be logged in to download this file
  requireUser integer not null default 0,

  primary key (id)
);

-- these are mailing list subscriptions
drop table if exists subscription_types;
create table subscription_types (
  id integer not null auto_increment,

  -- name as listed to users on the user options page, and as listed
  -- on the subscriptions management page
  name varchar(80) not null,

  -- the default title put into the article, and used for the article title 
  -- field when generating the article
  title varchar(64) not null,

  -- a description for the subscription
  -- used on user options page to give more info about a subscription
  description text not null,

  -- description of the frequency of subscriptions
  -- eg. "weekly", "Every Monday and Thursday"
  frequency varchar(127) not null,

  -- keyword field for the generated article
  keyword varchar(255) not null,

  -- do we archive the email to an article?
  archive integer not null default 1,

  -- template used when we build the article
  article_template varchar(127) not null,

  -- one or both of the following template needs to be defined
  -- if you only define the html template then the email won't be sent
  -- to users who only accept text emails
  -- template used for the HTML portion of the email
  html_template varchar(127) not null,

  -- template used for the text portion of the email
  text_template varchar(127) not null,

  -- which parent to put the generated article under
  -- can be 0 to indicate no article is generated
  parentId integer not null,

  -- the last time this was sent out
  lastSent datetime not null default '0000-00-00 00:00',

  -- if this is non-zero then the subscription is visible to users
  visible integer not null default 1,  
  
  primary key (id)
);

-- which lists users are subscribed to
drop table if exists subscribed_users;
create table subscribed_users (
  id integer not null auto_increment,
  subId integer not null,
  userId integer not null,
  primary key(id),
  unique (subId, userId)  
);

-- contains web site users
-- there will be a separate admin users table at some point
drop table if exists site_users;
create table site_users (
  id integer not null auto_increment,

  userId varchar(40) not null,
  password varchar(40) not null,
  email varchar(255) not null,

  keepAddress integer not null default 1,
  whenRegistered datetime not null,
  lastLogon datetime not null,

  -- used to fill in the checkout form
  name1 varchar(127),
  name2 varchar(127),
  address varchar(127),
  city varchar(127),
  state varchar(40),
  postcode varchar(40),
  telephone varchar(80),
  facsimile varchar(80),
  country varchar(127),

  -- the user wants to receive the site newsletter if any
  -- this should default to NO
  -- this is probably ignored for now
  wantLetter integer not null default 0,

  -- if this is non-zero, we have permission to send email to this
  -- user
  confirmed integer not null default 0,

  -- the confirmation message we send to a user includes this value
  -- in the confirmation url
  confirmSecret varchar(40) not null default '',

  -- non-zero if we sent a confirmation message
  waitingForConfirmation integer not null default 0,

  textOnlyMail integer not null,

  title varchar(127),
  organization varchar(127),
  
  referral integer,
  otherReferral varchar(127) not null,
  prompt integer,
  otherPrompt varchar(127) not null,
  profession integer not null,
  otherProfession varchar(127) not null,

  previousLogon datetime not null,

  -- used for billing information on the checkout form
  billFirstName varchar(127) not null default '',
  billLastName varchar(127) not null default '',
  billStreet varchar(127) not null default '',
  billSuburb varchar(127) not null default '',
  billState varchar(40) not null default '',
  billPostCode varchar(40) not null default '',
  billCountry varchar(127) not null default '',

  instructions text not null default '',
  billTelephone varchar(80) not null default '',
  billFacsimile varchar(80) not null default '',
  billEmail varchar(255) not null default '',

  adminNotes text not null default '',

  disabled integer not null default 0,

  flags varchar(80) not null default '',

  customText1 text,
  customText2 text,
  customText3 text,
  customStr1 varchar(255),
  customStr2 varchar(255),
  customStr3 varchar(255),

  affiliate_name varchar(40) not null default '',

  delivMobile varchar(80) not null default '',
  billMobile varchar(80) not null default '',

  delivStreet2 varchar(127) not null default '',
  billStreet2 varchar(127) not null default '',

  billOrganization varchar(127) not null default '',

  primary key (id),
  unique (userId),
  index (affiliate_name)
);

-- this is used to track email addresses that we've sent subscription
-- confirmations to
-- this is used to prevent an attacked creating a few hundred site users
-- and having the system send confirmation requests to those users
-- we make sure we only send one confirmation request per 48 hours
-- and a maximum of 3 unacknowledged confirmation requests
-- once the 3rd confirmation request is sent we don't send the user
-- any more requests - ever
--
-- each confirmation message also includes a blacklist address the 
-- recipient can use to add themselves to the blacklist
--
-- We don't have an unverified mechanism to add users to the blacklist
-- since someone could use this as a DoS.
--
-- Once we receive an acknowledgement from the recipient we remove them 
-- from this table.
drop table if exists email_requests;
create table email_requests (
  -- the table/row classes need this for now
  id integer not null auto_increment,

  # the actual email address the confirmation was sent to
  email varchar(127) not null,

  # the genericized email address
  genEmail varchar(127) not null,

  -- when the last confirmation email was sent
  lastConfSent datetime not null default '0000-00-00 00:00:00',

  -- how many confirmation messages have been sent
  unackedConfMsgs integer not null default 0,

  primary key (id),
  unique (email),
  unique (genEmail)
);

-- these are emails that someone has asked not to be subscribed to 
-- any mailing list
drop table if exists email_blacklist;
create table email_blacklist (
  -- the table/row classes need this for now
  id integer not null auto_increment,
  email varchar(127) not null,

  -- a short description of why the address was blacklisted
  why varchar(80) not null,

  primary key (id),
  unique (email)
);

drop table if exists admin_base;
create table admin_base (
  id integer not null auto_increment,
  type char not null,
  primary key (id)
);

drop table if exists admin_users;
create table admin_users (
  base_id integer not null,
  logon varchar(60) not null,
  name varchar(255) not null,
  password varchar(80) not null,
  perm_map varchar(255) not null,
  primary key (base_id),
  unique (logon)
);

drop table if exists admin_groups;
create table admin_groups (
  base_id integer not null,
  name varchar(80) not null,
  description varchar(255) not null,
  perm_map varchar(255) not null,
  primary key (base_id),
  unique (name)
);

drop table if exists admin_membership;
create table admin_membership (
  user_id integer not null,
  group_id integer not null,
  primary key (user_id, group_id)
);

drop table if exists admin_perms;
create table admin_perms (
  object_id integer not null,
  admin_id integer not null,
  perm_map varchar(255),
  primary key (object_id, admin_id)
);

-- -- these are "product" subscriptions
drop table if exists bse_subscriptions;
create table bse_subscriptions (
  subscription_id integer not null auto_increment primary key,

  text_id varchar(20) not null,

  title varchar(255) not null,

  description text not null,

  max_lapsed integer not null,

  unique (text_id)
);

drop table if exists bse_user_subscribed;
create table bse_user_subscribed (
  subscription_id integer not null,
  siteuser_id integer not null,
  started_at date not null,
  ends_at date not null,
  max_lapsed integer not null,
  primary key (subscription_id, siteuser_id)
);

drop table if exists bse_siteuser_images;
create table bse_siteuser_images (
  siteuser_id integer not null,
  image_id varchar(20) not null,
  filename varchar(80) not null,
  width integer not null,
  height integer not null,
  bytes integer not null,
  content_type varchar(80) not null,
  alt varchar(255) not null,

  primary key(siteuser_id, image_id)
);

drop table if exists bse_locations;
create table bse_locations (
  id integer not null auto_increment,
  description varchar(255) not null,
  room varchar(40) not null,
  street1 varchar(255) not null,
  street2 varchar(255) not null,
  suburb varchar(255) not null,
  state varchar(80) not null,
  country varchar(80) not null,
  postcode varchar(40) not null,
  public_notes text not null,

  bookings_name varchar(80) not null,
  bookings_phone varchar(80) not null,
  bookings_fax varchar(80) not null,
  bookings_url varchar(255) not null,
  facilities_name varchar(255) not null,
  facilities_phone varchar(80) not null,

  admin_notes text not null,

  disabled integer not null default 0,

  primary key(id)
);

drop table if exists bse_seminars;
create table bse_seminars (
  seminar_id integer not null primary key,
  duration integer not null
);

drop table if exists bse_seminar_sessions;
create table bse_seminar_sessions (
  id integer not null auto_increment,
  seminar_id integer not null,
  location_id integer not null,
  when_at datetime not null,
  roll_taken integer not null default 0,

  primary key (id),
  unique (seminar_id, location_id, when_at),
  index (seminar_id),
  index (location_id)
);

drop table if exists bse_seminar_bookings;
create table bse_seminar_bookings (
  session_id integer not null,
  siteuser_id integer not null,
  roll_present integer not null default 0,

  primary key(session_id, siteuser_id),
  index (siteuser_id)
);
