-- represents sections, articles

CREATE TABLE article (
  id integer DEFAULT '0' NOT NULL auto_increment,

  -- 0 for the entry page
  -- -1 for top-level sections (shown in side menu)
  parentid integer DEFAULT '0' NOT NULL,

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
  release datetime DEFAULT '0000-00-00 00:00:00' NOT NULL,
  expire datetime DEFAULT '9999-12-31 23:59:59' NOT NULL,
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
  summaryLength smallint(5) unsigned DEFAULT '200' NOT NULL,

  -- the class whose generate() method generates the page
  generator varchar(20) not null default 'article',

  -- the level of the article, 1 for top-level
  level smallint not null,

  -- for listed:
  -- 0 - don't list
  -- 1 - list everywhere
  -- 2 - list in sections, but not on the menu
  listed smallint not null default 1,
  -- date last modified
  lastModified date not null,
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
CREATE TABLE searchindex (
  id varchar(200) binary DEFAULT '' NOT NULL,
  -- a comma-separated lists of article and section ids
  articleIds varchar(255) default '' not null,
  sectionIds varchar(255) default '' not null,
  scores varchar(255) default '' not null,
  PRIMARY KEY (id)
);

#
# Table structure for table 'image'
#
CREATE TABLE image (
  id mediumint(8) unsigned NOT NULL auto_increment,
  articleId integer not null,
  image varchar(64) DEFAULT '' NOT NULL,
  alt varchar(255) DEFAULT '[Image]' NOT NULL,
  width smallint(5) unsigned,
  height smallint(5) unsigned,
  PRIMARY KEY (id)
);

# used for session tracking with Apache::Session::MySQL
CREATE TABLE sessions (
  id char(32) not null primary key,
  a_session text,
  -- so we can age this table
  whenChanged timestamp
);

-- these share data with the article table
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
  
  primary key(articleId)
);

-- order is a reserved word
-- I couldn't think of/find another word here
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

  primary key (id),
  index order_cchash(ccNumberHash)
);

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

  primary key (id),
  index order_item_order(orderId, id)
);
