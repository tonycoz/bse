#!/usr/bin/perl -w
# Builds an initial database
# make sure you set the appropriate values in cgi-bin/modules/Constants.pm

use strict;
use lib '../cgi-bin/modules';
use DBI;
use Article;
use Constants qw($DBD $DB $UN $PW $SECURLBASE $CGI_URI $SHOP_URI $ROOT_URI);

my @prebuilt =
  (
   # the section that represent's the index page
   {
    id=>1,
    parentid=>-1,
    displayOrder=>100, # doesn't matter
    title=>"My site's title",
    titleImage=>'your_site.gif',
    body=>'',
    imagePos=>'tr',
    release=>'0000-00-00 00:00:00',
    expire=>'9999-12-31 23:59:59',
    lastModified=>'2000-11-27 14:00:00',
    keyword=>'',
    template=>'index.tmpl',
    link=>$ROOT_URI . 'index.html',
    admin=>$CGI_URI.'/admin/admin.pl?id=1',
    threshold=>10000, # needs to be high
    summaryLength => 1000, # should be ignored
    generator=>'Generate::Article',
    thumbImage=>'',
    thumbWidth=>0,
    thumbHeight=>0,
    level=>1,
    listed=>1,
   },
   {
    # the invisible subsection for what's hot
    id=>2,
    parentid=>1,
    displayOrder=>100, # doesn't matter
    title=>"[index subsection]",
    titleImage=>'',
    body=>'',
    imagePos=>'tr',
    release=>'0000-00-00 00:00:00',
    expire=>'9999-12-31 23:59:59',
    lastModified=>'2000-11-27 14:00:00',
    keyword=>'',
    template=>'index2.tmpl',
    link=>'',
    admin=>$CGI_URI.'/admin/admin.pl?id=1',
    threshold=>10000, # needs to be high
    summaryLength => 1000, # should be ignored
    generator=>'Generate::Article',
    thumbImage=>'',
    thumbWidth=>0,
    thumbHeight=>0,
    level=>2,
    listed=>2,
   },
   {
    id=>3,
    parentid=>-1,
    displayOrder=>10000,
    title=>'The Shop',
    titleImage=>'the_shop.gif',
    body=>'You can buy things here',
    imagePos=>'tr',
    release=>'0000-00-00 00:00:00',
    expire=>'9999-12-31 23:59:59',
    lastModified=>'2000-11-27 14:00:00',
    keyword=>'shop',
    template=>'shop_sect.tmpl',
    link=>$SECURLBASE.$SHOP_URI.'/index.html',
    admin=>$CGI_URI.'/admin/admin.pl?id=3',
    threshold=>1000, # ignored
    summaryLength=>1000, # ignored
    generator=>'Generate::Article',
    thumbImage=>'',
    thumbWidth=>0,
    thumbHeight=>0,
    level=>1,
    listed=>1,
   },
   {
    id=>4,
    parentid=>3,
    displayOrder=>10000,
    title=>'[shop subsection]',
    titleImage=>'',
    body=>'', # don't set this - set the shop body instead
    imagePos=>'tr',
    release=>'0000-00-00 00:00:00',
    expire=>'9999-12-31 23:59:59',
    lastModified=>'2000-11-27 14:00:00',
    keyword=>'',
    template=>'catalog.tmpl',
    link=>'',
    admin=>$CGI_URI.'/admin/shopadmin.pl',
    threshold=>1000, # ignored
    summaryLength=>1000, #ignored
    generator=>'Generate::Catalog',
    thumbImage=>'',
    thumbWidth=>0,
    thumbHeight=>0,
    level=>2,
    listed=>2,
   },
  );

my $dbh = DBI->connect("dbi:$DBD:$DB", $UN, $PW)
  or die "Cannot connect to database: ",DBI->errstr;
my @columns = Article->columns;
$dbh->do('delete from article')
  or die "Cannot delete articles: ",$dbh->errstr;
$dbh->do('delete from product')
  or die "Cannot delete from product: ", $dbh->errstr;
$dbh->do('delete from image')
  or die "delete from image: ",$dbh->errstr;
my $sql = 'insert into article values('.join(',', ('?') x @columns).')';
my $sth = $dbh->prepare($sql)
  or die "Cannot prepare $sql: ",$dbh->errstr;
for my $art (@prebuilt) {
  $sth->execute(@$art{@columns})
    or die "Cannot insert row into article: ",$sth->errstr;
}
$dbh->disconnect();
