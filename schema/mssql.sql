-- you might want to limit the space here (or create the database with
-- the GUI tools)
-- create database bse
--   on (
--   name=bse_dat,
--   filename='e:\msde\data\bse.mdf'
-- )
-- go
drop procedure bse_update_article
go
drop procedure bse_add_article
go
drop proc bse_get_articles
go
drop proc bse_get_an_article
go
drop proc bse_articles_by_level
go
drop proc bse_articles_by_parent
go
drop proc bse_delete_article
go
drop table article
go
CREATE TABLE article (
  id integer NOT NULL identity,
  -- 0 for the entry page
  -- -1 for top-level sections (shown in side menu)
  parentid integer DEFAULT 0 NOT NULL,

  -- the order to display articles in  
  -- used for ordering sibling articles
  displayOrder integer not NULL default 0,
  title varchar(64) DEFAULT '' NOT NULL,
  titleImage varchar(64) not null,
  body text NOT NULL,

  -- thumbnail image
  thumbImage varchar(64) not null default '',
  thumbWidth integer not null,
  thumbHeight integer not null,

  -- position of first image for this article
  imagePos char(2) not null,
  release datetime DEFAULT '2000-01-01 00:00:00' NOT NULL,
  expire datetime DEFAULT '2099-12-31 00:00:00' NOT NULL,
  keyword varchar(255),

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
  summaryLength integer DEFAULT '200' NOT NULL,

  -- the class whose generate() method generates the page
  generator varchar(20) not null default 'article',

  -- the level of the article, 1 for top-level
  artLevel integer not null,

  -- for listed:
  -- 0 - don't list
  -- 1 - list everywhere
  -- 2 - list in sections, but not on the menu
  listed smallint not null default 1,

  -- date last modified
  lastModified datetime not null default getdate(),
  PRIMARY KEY (id)
)
go
create index article_date_index on article
(release, expire, id)
go
create index article_displayOrder_index on article
(displayOrder)
go
create index article_parentId_index on article
(parentId)
go
create index article_level_index on article
(artLevel, id)
go
drop proc bse_clear_search_index
go
drop proc bse_add_searchindex
go
drop proc bse_search
go
drop proc bse_search_wc
go
DROP TABLE searchindex
go
CREATE TABLE searchindex (
  id varbinary(200) NOT NULL,
  -- a comma-separated lists of article and section ids
  articleIds varchar(255) default '' not null,
  sectionIds varchar(255) default '' not null,
  scores varchar(255) default '' not null,
  PRIMARY KEY (id)
)
go
drop procedure bse_add_image
go
drop procedure bse_update_image
go
drop proc bse_get_images
go
drop proc bse_delete_image
go
drop proc bse_get_article_images
go
DROP TABLE image
go
CREATE TABLE image (
  id integer NOT NULL identity,  
  articleId integer not null,
  image varchar(64) DEFAULT '' NOT NULL,
  alt varchar(255) DEFAULT '[Image]' NOT NULL,
  width integer,
  height integer,
  url varchar(255),
  PRIMARY KEY (id)
)
go
DROP TABLE sessions
go
CREATE TABLE sessions (
  id char(32) not null primary key,
  a_session image,
  -- so we can age this table
 
 whenChanged timestamp
)
go
drop procedure bse_update_product
go
drop procedure bse_add_product
go
drop proc bse_get_products
go
drop proc bse_get_a_product
go
DROP TABLE product
go
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

  options varchar(255) not null,
  
  primary key(articleId)
)
go
drop procedure bse_add_order
go
drop procedure bse_update_order
go
drop procedure bse_get_orders
go
drop procedure bse_get_an_order
DROP TABLE orders
go
create table orders (
  id integer not null identity,

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

  primary key (id)
)
go
create index order_cchash on orders
(ccNumberHash)
go
drop proc bse_add_order_item
go
drop proc bse_order_items_by_order
go
DROP TABLE order_item;
create table order_item (
  id integer not null identity,
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

  options varchar(255) not null,
  
  primary key (id)
)
go
create index order_item_order on order_item
(orderId, id)
go
create procedure bse_update_article
   @id integer,
   @parentid integer,
   @displayOrder integer,
   @title varchar(64),
   @titleImage varchar(64),
   @body text,
   @thumbImage varchar(64),
   @thumbWidth integer,
   @thumbHeight integer,
   @imagePos char(2),
   @release datetime,
   @expire datetime,
   @keyword varchar(255),
   @template varchar(127),
   @link varchar(64),
   @admin varchar(64),
   @threshold integer,
   @summaryLength integer,
   @generator varchar(20),
   @artLevel integer,
   @listed integer,
   @lastModified datetime
as
  update article set parentid = @parentid, displayOrder = @displayOrder, 
	title = @title, titleImage = @titleImage, body = @body, 
	thumbImage = @thumbImage, thumbWidth = @thumbWidth, 
	thumbHeight = @thumbHeight, imagePos = @imagePos, 
	release = @release, expire = @expire, keyword = @keyword, 
	template = @template, link = @link, admin = @admin, 
	threshold = @threshold, summaryLength = @summaryLength, 
	generator = @generator, artLevel = @artLevel, listed = @listed, 
	lastModified = @lastModified
  where id = @id
go
create procedure bse_add_article
   @parentid integer,
   @displayOrder integer,
   @title varchar(64),
   @titleImage varchar(64),
   @body text,
   @thumbImage varchar(64),
   @thumbWidth integer,
   @thumbHeight integer,
   @imagePos char(2),
   @release datetime,
   @expire datetime,
   @keyword varchar(255),
   @template varchar(127),
   @link varchar(64),
   @admin varchar(64),
   @threshold integer,
   @summaryLength integer,
   @generator varchar(20),
   @artLevel integer,
   @listed integer,
   @lastModified datetime
as
  insert into article(parentid, displayOrder, title, titleImage, body,
	thumbImage, thumbWidth, thumbHeight, imagePos, release, expire,
	keyword, template, link, admin, threshold, summaryLength, 
	generator, artLevel, listed, lastModified)
  values (@parentid, @displayOrder, @title, @titleImage, @body, @thumbImage, 
	@thumbWidth, @thumbHeight, @imagePos, @release, @expire, @keyword, 
	@template, @link, @admin, @threshold, @summaryLength, @generator, 
	@artLevel, @listed, @lastModified)
go
create proc bse_get_articles
as
  select * from article
go
create proc bse_get_an_article
  @id integer
as
  select * from article where id = @id
go
create proc bse_articles_by_level
  @artLevel integer
as
  select * from article where artLevel = @artLevel
go
create proc bse_articles_by_parent
  @parentid integer
as
  select * from article where parentid = @parentid
go
create proc bse_delete_article
  @id integer
as
  delete from article where id = @id
go
create proc bse_get_images
as
  select * from image
go
create proc bse_delete_image
  @id integer
as
  delete from image where id = @id
go
create procedure bse_update_image
  @id integer,
  @articleId integer,
  @image varchar(64),
  @alt varchar(255),
  @width integer,
  @height integer
as
  update image
   set articleId = @articleId, image = @image, alt = @alt, width = @width, 
	height = @height
   where id = @id
go
create procedure bse_add_image
  @articleId integer,
  @image varchar(64),
  @alt varchar(255),
  @width integer,
  @height integer
as
  insert into image(articleId, image, alt, width, height)
	values(@articleId, @image, @alt, @width, @height)
go
create proc bse_get_article_images
  @articleId integer
as
  select * from image where articleId = @articleId
go
create procedure bse_update_product
  @articleId integer,
  @summary varchar(255),
  @leadTime integer,
  @retailPrice integer,
  @wholesalePrice integer,
  @gst integer,
  @options varchar(255)
as
  update product
   set summary = @summary, leadTime = @leadTime, retailPrice = @retailPrice, 
	wholesalePrice = @wholesalePrice, gst = @gst, options = @options
   where articleId = @articleId
go
create procedure bse_add_product
  @articleId integer,
  @summary varchar(255),
  @leadTime integer,
  @retailPrice integer,
  @wholesalePrice integer,
  @gst integer,
  @options varchar(255)
as
  insert into product(articleId, summary, leadTime, retailPrice, 
	wholesalePrice, gst, options)
  values(@articleId, @summary, @leadTime, @retailPrice, 
	@wholesalePrice, @gst, @options)
go
create proc bse_get_products
as
  select article.*, product.* from article, product where id = articleId
go
create proc bse_get_a_product
  @id integer
as
  select article.*, product.* from article, product 
  where id=@id and articleId = id
go

create proc bse_clear_search_index
as
  delete from searchindex
go
create proc bse_add_searchindex
  @phrase varchar(200),
  @articleIds varchar(255),
  @sectionIds varchar(255),
  @scores varchar(255)
as
  insert into searchindex values(cast(@phrase as varbinary(200)), @articleIds, @sectionIds, @scores)
go
create proc bse_search
  @phrase varchar(200)
as
  select * from searchindex where id = cast(@phrase as varbinary)
go
create proc bse_search_wc
  @phrase varbinary(200)
as
  select * from searchindex where id like @phrase
go
create proc bse_add_order
  @delivFirstName  varchar(127),
  @delivLastName  varchar(127),
  @delivStreet  varchar(127),
  @delivSuburb  varchar(127),
  @delivState  varchar(40),
  @delivPostCode  varchar(40),
  @delivCountry  varchar(127),
  @billFirstName  varchar(127),
  @billLastName  varchar(127),
  @billStreet  varchar(127),
  @billSuburb  varchar(127),
  @billState  varchar(40),
  @billPostCode  varchar(40),
  @billCountry  varchar(127),
  @telephone  varchar(80),
  @facsimile  varchar(80),
  @emailAddress  varchar(255),
  @total  integer,
  @wholesaleTotal  integer,
  @gst  integer,
  @orderDate  datetime,
  @ccNumberHash  varchar(127),
  @ccName  varchar(127),
  @ccExpiryHash  varchar(127),
  @ccType  varchar(30),
  @filled integer,
  @whenFilled datetime,
  @whoFilled varchar(40),
  @paidFor integer,
  @paymentReceipt varchar(40),
  @randomId varchar(40),
  @cancelled integer
as
  insert into orders(delivFirstName, delivLastName, delivStreet, delivSuburb, 
	delivState, delivPostCode, delivCountry, billFirstName, billLastName, 
	billStreet, billSuburb, billState, billPostCode, billCountry, 
	telephone, facsimile, emailAddress, total, wholesaleTotal, gst, 
	orderDate, ccNumberHash, ccName, ccExpiryHash, ccType,
	filled, whenFilled, whoFilled, paidFor, paymentReceipt, randomId,
	cancelled)
   values(@delivFirstName, @delivLastName, @delivStreet, @delivSuburb, 
	@delivState, @delivPostCode, @delivCountry, @billFirstName, 
	@billLastName, @billStreet, @billSuburb, @billState, @billPostCode, 
	@billCountry, @telephone, @facsimile, @emailAddress, @total, 
	@wholesaleTotal, @gst, @orderDate, @ccNumberHash, @ccName, 
	@ccExpiryHash, @ccType, @filled, @whenFilled, @whoFilled, @paidFor,
	@paymentReceipt, @randomId, @cancelled)

go

create proc bse_update_order
  @id integer,
  @delivFirstName  varchar(127),
  @delivLastName  varchar(127),
  @delivStreet  varchar(127),
  @delivSuburb  varchar(127),
  @delivState  varchar(40),
  @delivPostCode  varchar(40),
  @delivCountry  varchar(127),
  @billFirstName  varchar(127),
  @billLastName  varchar(127),
  @billStreet  varchar(127),
  @billSuburb  varchar(127),
  @billState  varchar(40),
  @billPostCode  varchar(40),
  @billCountry  varchar(127),
  @telephone  varchar(80),
  @facsimile  varchar(80),
  @emailAddress  varchar(255),
  @total  integer,
  @wholesaleTotal  integer,
  @gst  integer,
  @orderDate  datetime,
  @ccNumberHash  varchar(127),
  @ccName  varchar(127),
  @ccExpiryHash  varchar(127),
  @ccType  varchar(30),
  @filled integer,
  @whenFilled datetime,
  @whoFilled varchar(40),
  @paidFor integer,
  @paymentReceipt varchar(40),
  @randomId varchar(40),
  @cancelled integer
as
  update orders
	set delivFirstName = @delivFirstName, delivLastName = @delivLastName, 
	delivStreet = @delivStreet, delivSuburb = @delivSuburb, 
	delivState = @delivState, delivPostCode = @delivPostCode, 
	delivCountry = @delivCountry, billFirstName = @billFirstName, 
	billLastName = @billLastName, billStreet = @billStreet, 
	billSuburb = @billSuburb, billState = @billState, 
	billPostCode = @billPostCode, billCountry = @billCountry, 
	telephone = @telephone, facsimile = @facsimile, 
	emailAddress = @emailAddress, total = @total, 
	wholesaleTotal = @wholesaleTotal, gst = @gst, 
	orderDate = @orderDate, ccNumberHash = @ccNumberHash, 
	ccName = @ccName, ccExpiryHash = @ccExpiryHash, ccType = @ccType,
	filled = @filled, whenFilled = @whenFilled, whoFilled = @whoFilled,
	paidFor = @paidFor, paymentReceipt = @paymentReceipt,
 	randomId = @randomId, cancelled = @cancelled
  where id = @id
go

create proc bse_get_orders
as
  select * from orders
go
create proc bse_get_an_order
  @id integer
as
  select * from orders where id = @id
go
create proc bse_add_order_item
  @productId integer,
  @orderId integer,
  @units integer,
  @price integer,
  @wholesalePrice integer,
  @gst integer,
  @options varchar(255)
as
  insert into order_item(productId, orderId, units, price, 
	wholesalePrice, gst, options)
   values(@productId, @orderId, @units, @price, @gst, @wholesalePrice,
	@options)
go
create proc bse_order_items_by_order
  @orderId integer
as
 select * from order_item where orderId = @orderId
go
