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
   {
    id=>5,
    parentid=>1,
    displayOrder=>10000,
    title=>'[sidebar subsection]',
    titleImage=>'',
    body=>'', # don't set this
    imagePos=>'tr',
    release=>'0000-00-00 00:00:00',
    expire=>'9999-12-31 23:59:59',
    lastModified=>'2000-11-27 14:00:00',
    keyword=>'',
    template=>'sidebar_section.tmpl',
    link=>'',
    admin=>$CGI_URI.'/admin/add.pl?id=5',
    threshold=>1000, # ignored
    summaryLength=>1000, #ignored
    generator=>'Generate::Article',
    thumbImage=>'',
    thumbWidth=>0,
    thumbHeight=>0,
    level=>2,
    listed=>0,
   },
   {
    id=>6,
    parentid=>2,
    displayOrder=>10000,
    title=>'[formatting guide]',
    titleImage=>'',
    body=><<EOS,
anchor[basic] b[Sample basic formatting:]
indent[link[/a/8.html|regular link text]

b[link[/a/8.html|bold link text]]

i[link[/a/8.html|italic link text]]

i[b[link[/a/8.html|bold italic link text]]]

link[http://www.visualthought.com.au|link to external web site]
]

align[center|Align center text (NB: American spelling)]

align[right|Align right text]

This is how you can make an email link: link[mailto:adriann@visualthought.com.au|email us here!]

hrcolor[100%|1|#ffffff] anchor[font]
b[Sample font sizing:] (use numbers 1 - 7 only)
indent[fontcolor[7|#6699CC|This is font size 7 and colour]

font[6|This is font size 6]

font[5|This is font size 5]

font[4|This is font size 4]

font[3|This is font size 3]

font[2|This is font size 2]

font[1|This is font size 1]

(but they can be minus numbers too)

font[-2|This is font size -2]

font[-3|This is font size -3]

(or positive numbers)

font[+1|This is font size +1]

]

b[HINT:] The default font size for your body text is size 2 and the
headings are size 4 Bold.

hrcolor[100%|1|#ffffff] anchor[indent]
b[Sample indenting and bullet points:]
indent[This is a simple indent and bullet list
** Add a bullet point to this line
** Hit enter and type another
** And now one final bullet

## And this is a numbered list
## It's very easy to format lists now
## Now we can count to three]

hrcolor[100%|1|#ffffff]
b[The NSWFITC colours:]
indent[
table[bgcolor=#ffffff width=170 cellpadding=5
|fontcolor[2|#000000|White - #FFFFFF]
]
table[bgcolor=#6699CC width=170 cellpadding=5
|fontcolor[2|#000000|Light Blue - #6699CC]
]
table[bgcolor=#336699 width=170 cellpadding=5
|fontcolor[2|#ffffff|Medium Blue - #336699]
]
table[bgcolor=#336699 width=170 cellpadding=1 cellspacing=0 |table[bgcolor=#003366 width=100% cellspacing=0 cellpadding=5
|fontcolor[2|#ffffff|Regular Blue - #003366]
]]
table[bgcolor=#000033 width=170 cellpadding=5
|fontcolor[2|#ffffff|Dark Blue - #000033]
]
]
hrcolor[100%|1|#ffffff]
b[Sample links to an anchor:]
indent[link[#basic|Jump to "Sample basic formatting"]
link[#font|Jump to "Sample font sizing"]
r link[#indent|Jump to "Sample indenting and bullet points"]
link[#table|Jump to "Making a table"]]


hrcolor[100%|1|#ffffff] anchor[table]
b[Making a table:]
indent[
BSE has special tags to create simple tables, but if you wish to do anything more complicated, we recommend you develop the table in HTML and insert the raw HTML into the body text field.

table[
|a very|simple
|table|with 4 cells
]

table[bgcolor=#6699CC width=90% cellpadding=5
|align[center|link[/a/2.html|this one]]|is
|not so|simple
]


table[width=100% cellpadding=5
|b[font[2|Project Management]]|font[2|Project management services for buildings, infrastructure, technology and environment, relocations.]
|b[font[2|Events]]|font[2|Event marketing and management, overlay works, venue management.]
|b[font[2|Property]]|font[2|Property development management and advisory.] 
|b[font[2|Management Consulting]]|font[2|Business improvement, change management, market testing, outsourcing, contracts and relationships, industrial relations, safety, asset management.]
|b[font[2|Quality Assurance]]|font[2|Independent 3rd party audits, quality systems, certification, OHS&R programmes.]
]
]

hrcolor[100%|1|#ffffff]
EOS
    imagePos=>'tr',
    release=>'0000-00-00 00:00:00',
    expire=>'9999-12-31 23:59:59',
    lastModified=>'2000-11-27 14:00:00',
    keyword=>'',
    template=>'sidebar_section.tmpl',
    link=>'',
    admin=>$CGI_URI.'/admin/add.pl?id=5',
    threshold=>1000, # ignored
    summaryLength=>1000, #ignored
    generator=>'Generate::Article',
    thumbImage=>'',
    thumbWidth=>0,
    thumbHeight=>0,
    level=>2,
    listed=>0,
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
