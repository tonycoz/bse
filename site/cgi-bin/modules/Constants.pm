package Constants;
use strict;

# this needs to be re-organized
use vars qw(@EXPORT_OK %EXPORT_TAGS @ISA $VERSION 
$DBD $DB $UN $PW $D_00 $D_99 $D_XX
$L_ID $TMPLDIR $IMAGEDIR $SEP $URLBASE $SECURLBASE %LEVEL_DEFAULTS $BASEDIR
$MAXPHRASE $CONTENTBASE $SHOPID $PRODUCTPARENT $DATADIR $LINK_TITLES 
@SEARCH_EXCLUDE @SEARCH_INCLUDE $SEARCH_LEVEL $SEARCH_ALL
$SEARCH_WILDCARD_MIN $SEARCH_AUTO_WILDCARD
%TEMPLATE_OPTS %EXTRA_TAGS @NO_DELETE
$SHOP_MAIL_SUBJECT $SHOP_PASSPHRASE $SHOP_CRYPTO $SHOP_SIGNING_ID
$SHOP_GPG $SHOP_PGP $SHOP_FROM $SHOP_TO_NAME $SHOP_TO_EMAIL $SHOP_SENDMAIL
$SHOP_PGPE $SHOP_EMAIL_ORDER
$ROOT_URI $ARTICLE_URI $SHOP_URI $CGI_URI $ADMIN_URI $IMAGES_URI
$LOCAL_FORMAT $GENERATE_BUTTON $AUTO_GENERATE
$DATA_EMAIL $MYSQLDUMP $BODY_EMBED $EMBED_MAX_DEPTH $REPARENT_UPDOWN
$HAVE_HTML_PARSER);

$VERSION = 0.1;

require Exporter;
@ISA = qw/Exporter/;
@EXPORT_OK = qw/$DBD $DB $UN $PW $D_00 $D_99 $D_XX $L_ID $TMPLDIR $SEP 
$IMAGEDIR $URLBASE $SECURLBASE %LEVEL_DEFAULTS $BASEDIR $MAXPHRASE 
$CONTENTBASE $SHOPID $PRODUCTPARENT $DATADIR $LINK_TITLES 
@SEARCH_EXCLUDE @SEARCH_INCLUDE $SEARCH_LEVEL $SEARCH_ALL
$SEARCH_WILDCARD_MIN $SEARCH_AUTO_WILDCARD
%TEMPLATE_OPTS %EXTRA_TAGS @NO_DELETE
$SHOP_MAIL_SUBJECT $SHOP_PASSPHRASE $SHOP_CRYPTO 
$SHOP_SIGNING_ID $SHOP_GPG $SHOP_PGP $SHOP_FROM 
$SHOP_TO_NAME $SHOP_TO_EMAIL $SHOP_EMAIL_ORDER $SHOP_SENDMAIL $SHOP_PGPE
$ROOT_URI $ARTICLE_URI $SHOP_URI $CGI_URI $ADMIN_URI $IMAGES_URI
$LOCAL_FORMAT $GENERATE_BUTTON $AUTO_GENERATE
$DATA_EMAIL $MYSQLDUMP $BODY_EMBED $EMBED_MAX_DEPTH $REPARENT_UPDOWN
$HAVE_HTML_PARSER/;

%EXPORT_TAGS =
  (
   shop=> [ qw/$SHOP_MAIL_SUBJECT $SHOP_PASSPHRASE $SHOP_CRYPTO 
               $SHOP_SIGNING_ID $SHOP_GPG $SHOP_PGP $SHOP_FROM 
               $SHOP_TO_NAME $SHOP_TO_EMAIL $SHOP_SENDMAIL $SHOP_PGPE
               $SHOP_EMAIL_ORDER $SHOP_URI/ ],
   edit=> [ qw/$TMPLDIR $IMAGEDIR $D_00 $D_99 $URLBASE @NO_DELETE 
               $SECURLBASE $ARTICLE_URI $CGI_URI $SHOP_URI $ROOT_URI
	       $AUTO_GENERATE $REPARENT_UPDOWN/ ],
   search => [ qw/$TMPLDIR @SEARCH_EXCLUDE @SEARCH_INCLUDE $SEARCH_ALL
                  $SEARCH_WILDCARD_MIN $SEARCH_AUTO_WILDCARD/ ],
  );

$DBD = 'mysql';

$DB = 'bse';

$UN = 'root';
$PW = '';

$L_ID = 'mysql_insertid';

# base directory of the site
$BASEDIR = '/home/httpd/html/common/work/bse/site';

# where we keep templates
$TMPLDIR = $BASEDIR.'/templates/';

# where the html is kept
$CONTENTBASE = $BASEDIR . '/htdocs/';

# where we keep images
$IMAGEDIR = $CONTENTBASE.'images/';

# where we keep some data files (like stopwords.txt)
$DATADIR = $BASEDIR.'/data/';

# how the outside world sees our site
$URLBASE = "http://bse.earth";
$SECURLBASE = "http://sec.bse.earth";

# the base directories for articles and the shop
# relative to $CONTENTBASE except for $CGI_URI
# you shouldn't need to modify these
$ROOT_URI = '/';
$ARTICLE_URI = $ROOT_URI."a";
$SHOP_URI = $ROOT_URI."shop";
$ADMIN_URI = $ROOT_URI."admin/";
$IMAGES_URI = $ROOT_URI."images";
$CGI_URI = "/cgi-bin";

# level defaults
%LEVEL_DEFAULTS = 
  (
   0=>{
       display=>"Your Site",
      },
    
   1=>{
       threshold=>1,
       template=>'common/default.tmpl',
       display=>'Section',
      },
   2=>{
       threshold=>3,
       template=>'common/default.tmpl',
       display=>'Subsect Lev1',
      },
   3=>{
       threshold=>100000,
       template=>'common/default.tmpl',
       display=>'Subsect Lev2',
      },
   4=>{
       threshold=>10,
       template=>'common/default.tmpl',
       display=>'Subsect Lev3',
      },
   5=>{
       threshold=>10,
       template=>'common/default.tmpl',
       display=>"Subsect Lev4",
      },
  );

# set this to zero to disable adding titles to the end of links
# eg. with this on, if article id 5 has a title of "hello world", then
# links to it will be: /a/5.html/hello_world
# the aim of this is if a search engine indexes on the url, it has something
# useful to index on
# To make this work with Apache, put the following in the .htaccess file
# in the /a/ directory:
#   RewriteEngine On
#   RewriteRule ^([0-9]+\.html)/[0-9a-zA-Z_]*$ ./$1 [T=text/html]
$LINK_TITLES = 0;

# sections to exclude from the search
@SEARCH_EXCLUDE = ( 1 );

# sections to include in the search section drop-down, even if unlisted
@SEARCH_INCLUDE = ();

# any articles with a higher level than this are indexed as their ancestor 
# at this level
$SEARCH_LEVEL = 3;

# used to mean "all of site" in the search section drop-down
$SEARCH_ALL = "All Sections";

# non-zero to allow automatic wildcard searches
$SEARCH_AUTO_WILDCARD = 1;

# the minimum length of a wildcard search term
$SEARCH_WILDCARD_MIN = 4;

# defines extra tags added to the tags defined by Generate.pm
# constants are converted to subs automatically
# you cannot override existing tags
%EXTRA_TAGS =
  (
   siteName => 'My Site',
  );

# articles that cannot be deleted
# you don't need to include the shop ids here, they are always 
# protected
@NO_DELETE = ( 1, 2 );

# you can use the following to add local body formatting tags without
# having to modify Generate.pm and give yourself upgrade hassles
# the following should be a reference blessed into class with two methods:
#   body(\$body) - substitute your tags, return true if any tags replaced
#   clean(\$body) - remove any tags, return true if any tags replaced
$LOCAL_FORMAT = undef;

# controls whether or not the embed[] tags works in article bodies
$BODY_EMBED = 0;

# the maximum number of embedding levels
$EMBED_MAX_DEPTH = 20;

# controls whether or not the Regenerate button is displayed
# also whether generate.pl actually does something
# For normal scalars, non-zero means the button is displayed
# for a coderef, if a call to the coderef returns non-zero the button is 
# display
# for any other ref, if $GENERATE_BUTTON->want_button() is non-zero then
# the button is displayed
# you could assign a coderef that checks if the current user is
# in an admin group
$GENERATE_BUTTON = 1;

# if this is non-zero an articles and its ancestors are regenerated
# when the article is modified
$AUTO_GENERATE = 1;

# if this is non-zero then the user can reparent the article to a 
# different level
# this can be a coderef if you want, which returns non-zero if the
# user can reparent up/down
$REPARENT_UPDOWN = 0;

# this should be non-zero if you have HTML::Parser installed
# if non-zero then HTML::Parser will be used to strip HTML tags
# from <HTML> bodies and from html[] tags in bodies when the text is
# being displayed in either a table of contents summary or in 
# a search result excerpt.  It is also used to extract test for search
# indexing
$HAVE_HTML_PARSER = 1;

# shop configuration

# the cryto module used to encrypt your copy of the order
# this can also be Squirrel::PGP5 or Squirrel::PGP6, at least if they
# work...
$SHOP_CRYPTO = 'Squirrel::GPG';

# the passphrase for the secret key used to sign your copy of the order
$SHOP_PASSPHRASE = "";

# the id of the key
$SHOP_SIGNING_ID = '0x00000000';

# the path to the gpg program (if it isn't in the PATH)
# (only for Squirrel::GPG)
$SHOP_GPG = 'gpg';

# the path to the pgp program (if it isn't in the PATH)
# (only for Squirrel::PGP6)
$SHOP_PGP = 'pgp';

# the path to the pgpe program (if it isn't in the PATH)
# (only for Squirrel::PGP5)
$SHOP_PGPE = 'pgpe';

# where to find sendmail (or something compatible)
$SHOP_SENDMAIL = '/usr/lib/sendmail';

# subject for the email sent to customers upon filling in an order
$SHOP_MAIL_SUBJECT = "Your (web site) order";

# name used in the From line for both the order emails
$SHOP_FROM = 'you@yoursite.com';

# the name/email your copy of emailled orders should be sent to
$SHOP_TO_NAME = 'Your Name';
$SHOP_TO_EMAIL = 'sales@yoursite.com';

# non-zero if we should email an encrypted order to $SHOP_TO_EMAIL
$SHOP_EMAIL_ORDER = 0;

# Maintenance tools

# datadump.pl emails the dump to this address
$DATA_EMAIL = 'you@yoursite.com';

# the name of your copy of mysqldump (used by datadump.pl)
# if it's not in the PATH then give the absolute path here
$MYSQLDUMP = 'mysqldump';

###########################################################
### *** You should not need to modify the following *** ###
###########################################################

# maximum phrase length indexed
$MAXPHRASE = 5;

# the article (section) which is the online-store
# used to link to the shop
$SHOPID = 3;

# article that acts as the parent for products
# this must be the only child of $SHOPID
$PRODUCTPARENT = 4;


$SEP = "\x01";

$D_00 = '0000-00-00 00:00:00' ;
$D_99 = '9999-12-31 23:59:59' ;

use POSIX qw/strftime/; 
$D_XX = sub { strftime "%Y-%m-%d %H:%M:%S" => (localtime)[0..5] };

%TEMPLATE_OPTS = ( template_dir => $TMPLDIR );


1;
