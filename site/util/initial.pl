#!/usr/bin/perl -w
# Builds an initial database
# make sure you set the appropriate values in cgi-bin/modules/Constants.pm

use strict;
use lib '../cgi-bin/modules';
use DBI;
use BSE::TB::Article;
use Constants qw($DSN $UN $PW $CGI_URI $SHOP_URI $ROOT_URI);
use BSE::API qw(bse_init bse_cfg);
use BSE::Util::SQL qw(now_sqldate now_sqldatetime);

bse_init("../cgi-bin");
my $cfg = bse_cfg();
my $securlbase = $cfg->entryVar('site', 'secureurl');
my $nowDate = now_sqldate();
my $nowDatetime = now_sqldatetime();

my @prebuilt =
  (
   # the section that represent's the index page
   {
    id=>1,
    parentid=>-1,
    displayOrder=>100, # doesn't matter
    title=>"My site's title",
    titleImage=>'',
    body=>'',
    imagePos=>'tr',
    release=>"$nowDate 00:00:00",
    expire=>'9999-12-31 23:59:59',
    lastModified=>"$nowDatetime",
    keyword=>'',
    template=>'index.tmpl',
    link=>$ROOT_URI . '',
    admin=>$CGI_URI.'/admin/admin.pl?id=1',
    threshold=>10000, # needs to be high
    summaryLength => 1000, # should be ignored
    generator=>'BSE::Generate::Article',
    thumbImage=>'',
    thumbWidth=>0,
    thumbHeight=>0,
    level=>1,
    listed=>1,
    flags=>'',
    lastModifiedBy=>'system',
    created=>"$nowDatetime",
    createdBy=>'system',
    author=>'',
    pageTitle=>'',
    force_dynamic => 0,
    cached_dynamic => 0,
    inherit_siteuser_rights => 1,
    metaDescription=>'',
    metaKeywords=>'',
    summary => '',
    menu => 0,
    titleAlias => '',
    category => '',
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
    release=>"$nowDate 00:00:00",
    expire=>'9999-12-31 23:59:59',
    lastModified=>"$nowDatetime",
    keyword=>'',
    template=>'index2.tmpl',
    link=>'',
    admin=>$CGI_URI.'/admin/admin.pl?id=1',
    threshold=>10000, # needs to be high
    summaryLength => 1000, # should be ignored
    generator=>'BSE::Generate::Article',
    thumbImage=>'',
    thumbWidth=>0,
    thumbHeight=>0,
    level=>2,
    listed=>2,
    flags=>'',
    lastModifiedBy=>'system',
    created=>"$nowDatetime",
    createdBy=>'system',
    author=>'',
    pageTitle=>'',
    force_dynamic => 0,
    cached_dynamic => 0,
    inherit_siteuser_rights => 1,
    metaDescription=>'',
    metaKeywords=>'',
    summary => '',
    menu => 0,
    titleAlias => '',
    category => '',
   },
   {
    id=>3,
    parentid=>-1,
    displayOrder=>10000,
    title=>'The Shop',
    titleImage=>'',
    body=>'You can buy things here',
    imagePos=>'tr',
    release=>"$nowDate 00:00:00",
    expire=>'9999-12-31 23:59:59',
    lastModified=>"$nowDatetime",
    keyword=>'shop',
    template=>'shop_sect.tmpl',
    link=>$securlbase.$SHOP_URI.'/',
    admin=>$CGI_URI.'/admin/admin.pl?id=3',
    threshold=>1000, # ignored
    summaryLength=>1000, # ignored
    generator=>'BSE::Generate::Article',
    thumbImage=>'',
    thumbWidth=>0,
    thumbHeight=>0,
    level=>1,
    listed=>1,
    flags=>'',
    lastModifiedBy=>'system',
    created=>"$nowDatetime",
    createdBy=>'system',
    author=>'',
    pageTitle=>'',
    force_dynamic => 0,
    cached_dynamic => 0,
    inherit_siteuser_rights => 1,
    metaDescription=>'',
    metaKeywords=>'',
    summary => '',
    menu => 0,
    titleAlias => '',
    category => '',
   },
   {
    id=>4,
    parentid=>3,
    displayOrder=>10000,
    title=>'[shop subsection]',
    titleImage=>'',
    body=>'', # don't set this - set the shop body instead
    imagePos=>'tr',
    release=>"$nowDate 00:00:00",
    expire=>'9999-12-31 23:59:59',
    lastModified=>"$nowDatetime",
    keyword=>'',
    template=>'catalog.tmpl',
    link=>'',
    admin=>$CGI_URI.'/admin/shopadmin.pl',
    threshold=>1000, # ignored
    summaryLength=>1000, #ignored
    generator=>'BSE::Generate::Catalog',
    thumbImage=>'',
    thumbWidth=>0,
    thumbHeight=>0,
    level=>2,
    listed=>2,
    flags=>'',
    lastModifiedBy=>'system',
    created=>"$nowDatetime",
    createdBy=>'system',
    author=>'',
    pageTitle=>'',
    force_dynamic => 0,
    cached_dynamic => 0,
    inherit_siteuser_rights => 1,
    metaDescription=>'',
    metaKeywords=>'',
    summary => '',
    menu => 0,
    titleAlias => '',
    category => '',
   },
   {
    id=>5,
    parentid=>1,
    displayOrder=>10000,
    title=>'[sidebar subsection]',
    titleImage=>'',
    body=>'', # don't set this
    imagePos=>'tr',
    release=>"$nowDate 00:00:00",
    expire=>'9999-12-31 23:59:59',
    lastModified=>"$nowDatetime",
    keyword=>'',
    template=>'common/sidebar_section.tmpl',
    link=>'',
    admin=>$CGI_URI.'/admin/admin.pl?id=5',
    threshold=>1000, # ignored
    summaryLength=>1000, #ignored
    generator=>'BSE::Generate::Article',
    thumbImage=>'',
    thumbWidth=>0,
    thumbHeight=>0,
    level=>2,
    listed=>0,
    flags=>'',
    lastModifiedBy=>'system',
    created=>"$nowDatetime",
    createdBy=>'system',
    author=>'',
    pageTitle=>'',
    force_dynamic => 0,
    cached_dynamic => 0,
    inherit_siteuser_rights => 1,
    metaDescription=>'',
    metaKeywords=>'',
    summary => '',
    menu => 0,
    titleAlias => '',
    category => '',
   },
   {
    id=>6,
    parentid=>2,
    displayOrder=>10000,
    title=>'[formatting guide]',
    titleImage=>'',
    body=><<'EOS',
anchor[basic] b[Sample basic formatting:]
indent[link[/a/1.html|regular link text]

b[link[/a/1.html|bold link text]]

i[link[/a/1.html|italic link text]]

i[b[link[/a/1.html|bold italic link text]]]

link[http://www.google.com|link to external web site]
]

align[center|Align center text (NB: American spelling)]

align[right|Align right text]

This is how you can make an email link: link[mailto:adriann@devbox.org|email us here!]

hrcolor[100%|1|#CCCCFF] anchor[font]
b[Sample font sizing:] (use numbers 1 - 7 only)
indent[fontcolor[7|#FFCC33|This is font size 7 and colour]

font[6|This is font size 6]

font[5|This is font size 5]

font[4|This is font size 4]

font[3|This is font size 3]

font[2|This is font size 2]

font[1|This is font size 1]

(but they can be plus or minus numbers too)

font[+2|This is font size +2]

font[+3|This is font size +3]

font[-2|This is font size -2]

font[-3|This is font size -3]
]

b[HINT:] The default font size for your body text is size 2 and the headings are size 4 Bold.

hrcolor[100%|1|#CCCCFF] anchor[indent]
b[Sample indenting and bullet points:]
indent[This is a simple indent and bullet list
** Add a bullet point to this line
** Hit enter and type another
** And now one final bullet

## And this is a numbered list
## It's very easy to format lists now
## Now we can count to three]

hrcolor[100%|1|#CCCCFF]
b[The BSE colours:]
indent[
table[bgcolor=#999999 width=170 cellpadding=1 cellspacing=0 |table[bgcolor=#FFFFCC width=100% cellspacing=0 cellpadding=5
|fontcolor[2|#000000|Background - #FFFFCC]
]]
table[bgcolor=#FFFF99 width=170 cellpadding=5
|fontcolor[2|#000000|Navbar - #FFFF99]
]
table[bgcolor=#FFCC33 width=170 cellpadding=5
|fontcolor[2|#000000|Sidebar Title - #FFCC33]
]
table[bgcolor=#CCCCFF width=170 cellpadding=5
|fontcolor[2|#000000|Title Panel - #CCCCFF]
]
table[bgcolor=#333399 width=170 cellpadding=5
|fontcolor[2|#ffffff|Crumb Panel - #333399]
]
table[bgcolor=#999999 width=170 cellpadding=5
|fontcolor[2|#000000|Outlines - #999999]
]
table[bgcolor=#FFFFFF width=170 cellpadding=5
|fontcolor[2|#000000|Item Panel - #FFFFFF]
]
]
hrcolor[100%|1|#CCCCFF]
b[Sample links to an anchor:]
indent[link[#basic|Jump to "Sample basic formatting"]
link[#font|Jump to "Sample font sizing"]
link[#indent|Jump to "Sample indenting and bullet points"]
link[#table|Jump to "Making a table"]]


hrcolor[100%|1|#CCCCFF] anchor[table]
b[Making a table:]
indent[
BSE has special tags to create simple tables, but if you wish to do anything more complicated, we recommend you develop the table in HTML and insert the raw HTML into the body text field.

table[
|a very|simple
|table|with 4 cells
]

table[bgcolor=#CCCCFF width=90% cellpadding=5
|align[center|link[/a/1.html|this one]]|is
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

hrcolor[100%|1|#CCCCFF]

b[Inserting a plain HTML table:]

Use an HTML editor to create table like this, then paste the generated HTML code into the text body area as you would any normal text.

html[ 
<table width="100%" border="0" cellspacing="0" cellpadding="0" bgcolor="#999999">
  <tr>
    <td>
      <table width="100%" border="0" cellpadding="5" cellspacing="1">
        <tr bgcolor="#FFCC33"> 
          <td width="25%" height="18"> <b><font face="Verdana, Arial, Helvetica, sans-serif" size="2">PROJECT 
            MANAGEMENT</font></b></td>
          <td width="25%" height="18"> <b><font face="Verdana, Arial, Helvetica, sans-serif" size="2">MANAGEMENT 
            CONSULTING</font></b></td>
          <td width="25%" height="18"> <b><font face="Verdana, Arial, Helvetica, sans-serif" size="2">PROPERTY</font></b></td>
          <td width="25%" height="18"> <b><font face="Verdana, Arial, Helvetica, sans-serif" size="2">EVENTS</font></b></td>
        </tr>
        <tr valign="top" bgcolor="#FFFFCC"> 
          <td width="25%"> 
            <ul>
              <li><font face="Verdana, Arial, Helvetica, sans-serif" size="-2"> 
                Project assessment and initiation</font></li>
              <li><font face="Verdana, Arial, Helvetica, sans-serif" size="-2">Project 
                audit</font></li>
              <li><font face="Verdana, Arial, Helvetica, sans-serif" size="-2">Distressed 
                project recovery</font></li>
              <li><font face="Verdana, Arial, Helvetica, sans-serif" size="-2">Construction 
                advisory</font></li>
              <li><font face="Verdana, Arial, Helvetica, sans-serif" size="-2">Relocation 
                management </font></li>
            </ul>
          </td>
          <td width="25%"> 
            <ul>
              <li><font face="Verdana, Arial, Helvetica, sans-serif" size="-2">Business 
                improvement </font></li>
              <li><font face="Verdana, Arial, Helvetica, sans-serif" size="-2">Change 
                management</font></li>
              <li><font face="Verdana, Arial, Helvetica, sans-serif" size="-2">Market 
                testing and Outsourcing</font></li>
              <li><font face="Verdana, Arial, Helvetica, sans-serif" size="-2">Information 
                management</font></li>
              <li><font face="Verdana, Arial, Helvetica, sans-serif" size="-2">Employee 
                relations</font></li>
            </ul>
          </td>
          <td width="25%"> 
            <ul>
              <li><font face="Verdana, Arial, Helvetica, sans-serif" size="-2">Development 
                management and packaging</font></li>
              <li><font face="Verdana, Arial, Helvetica, sans-serif" size="-2">Property 
                asset strategy</font></li>
              <li><font face="Verdana, Arial, Helvetica, sans-serif" size="-2">Property 
                advisory</font></li>
              <li><font face="Verdana, Arial, Helvetica, sans-serif" size="-2">Property 
                workout</font></li>
            </ul>
          </td>
          <td width="25%"> 
            <ul>
              <li><font face="Verdana, Arial, Helvetica, sans-serif" size="-2">Event 
                management</font></li>
              <li><font face="Verdana, Arial, Helvetica, sans-serif" size="-2">Sponsorship 
                and marketing</font></li>
              <li><font face="Verdana, Arial, Helvetica, sans-serif" size="-2">Event 
                overlay works</font></li>
              <li><font face="Verdana, Arial, Helvetica, sans-serif" size="-2">Venue 
                management</font></li>
              <li><font face="Verdana, Arial, Helvetica, sans-serif" size="-2">Special 
                event consulting </font></li>
            </ul>
          </td>
        </tr>
        <tr valign="top" bgcolor="#003366 "> 
          <td colspan="4" bgcolor="#CCCCFF"><b><font face="Verdana, Arial, Helvetica, sans-serif" size="2">This 
            could be a subtitle</font></b> </td>
        </tr>
        <tr valign="top" bgcolor="#FFFFCC"> 
          <td width="25%"> <font face="Verdana, Arial, Helvetica, sans-serif" size="-2">Contract 
            and commercial </font></td>
          <td width="25%"> <font face="Verdana, Arial, Helvetica, sans-serif" size="-2">Asset 
            management </font></td>
          <td width="25%"> <font face="Verdana, Arial, Helvetica, sans-serif" size="-2">Project 
            Marketing</font><font face="Verdana, Arial, Helvetica, sans-serif" size="-2"> 
            Contract </font></td>
          <td width="25%"> <font face="Verdana, Arial, Helvetica, sans-serif" size="-2">Sponsorship</font></td>
        </tr>
        <tr valign="top" bgcolor="#FFFFCC"> 
          <td width="25%"> <font face="Verdana, Arial, Helvetica, sans-serif" size="-2">Project 
            information systems</font></td>
          <td width="25%"> <font face="Verdana, Arial, Helvetica, sans-serif" size="-2">Risk 
            management</font></td>
          <td width="25%"> <font face="Verdana, Arial, Helvetica, sans-serif" size="-2">Project 
            Marketing</font></td>
          <td width="25%"> <font face="Verdana, Arial, Helvetica, sans-serif" size="-2">Event 
            management</font></td>
        </tr>
        <tr valign="top" bgcolor="#FFFFCC"> 
          <td width="25%"> <font face="Verdana, Arial, Helvetica, sans-serif" size="-2">Independent 
            certification</font></td>
          <td width="25%"> <font face="Verdana, Arial, Helvetica, sans-serif" size="-2">Business 
            advisory</font></td>
          <td width="25%"> <font face="Verdana, Arial, Helvetica, sans-serif" size="-2">Feasibility 
            financial modelling</font></td>
          <td width="25%"> <font face="Verdana, Arial, Helvetica, sans-serif" size="-2">Event 
            overlay works</font></td>
        </tr>
      </table>
    </td>
  </tr>
</table>]
EOS
    imagePos=>'tr',
    release=>"$nowDate 00:00:00",
    expire=>'9999-12-31 23:59:59',
    lastModified=>"$nowDatetime",
    keyword=>'',
    template=>'common/default.tmpl',
    link=>'/a/format_guide.html',
    admin=>$CGI_URI.'/admin/admin.pl?id=6',
    threshold=>1000, # ignored
    summaryLength=>1000, #ignored
    generator=>'BSE::Generate::Article',
    thumbImage=>'',
    thumbWidth=>0,
    thumbHeight=>0,
    level=>3,
    listed=>0,
    flags=>'',
    lastModifiedBy=>'system',
    created=>"$nowDatetime",
    createdBy=>'system',
    author=>'',
    pageTitle=>'',
    force_dynamic => 0,
    cached_dynamic => 0,
    inherit_siteuser_rights => 1,
    metaDescription=>'',
    metaKeywords=>'',
    summary => '',
    menu => 0,
    titleAlias => '',
    category => '',
   },
   {
    id=>7,
    parentid=>2,
    displayOrder=>20000,
    title=>'[rss generation]',
    titleImage=>'',
    body=><<'EOS',
This body text is not used.

This article generates RSS as used by some sites.
EOS
    imagePos=>'tr',
    release=>"$nowDate 00:00:00",
    expire=>'9999-12-31 23:59:59',
    lastModified=>"$nowDatetime",
    keyword=>'',
    template=>'common/rssbase.tmpl',
    link=>'/a/site.rdf',
    admin=>$CGI_URI.'/admin/admin.pl?id=7',
    threshold=>1000, # ignored
    summaryLength=>1000, #ignored
    generator=>'BSE::Generate::Article',
    thumbImage=>'',
    thumbWidth=>0,
    thumbHeight=>0,
    level=>3,
    listed=>0,
    flags=>'',
    lastModifiedBy=>'system',
    created=>"$nowDatetime",
    createdBy=>'system',
    author=>'',
    pageTitle=>'',
    force_dynamic => 0,
    cached_dynamic => 0,
    inherit_siteuser_rights => 1,
    metaDescription=>'',
    metaKeywords=>'',
    summary => '',
    menu => 0,
    titleAlias => '',
    category => '',
   },
   {
    id=>8,
    parentid=>5,
    displayOrder=>20000,
    title=>'[sidebar logon]',
    titleImage=>'',
    body=><<'EOS',
This body text is not used.

This article puts a registration/login bar in the sidebar
EOS
    imagePos=>'tr',
    release=>"$nowDate 00:00:00",
    expire=>'9999-12-31 23:59:59',
    lastModified=>"$nowDatetime",
    keyword=>'',
    template=>'sidebar/logon.tmpl',
    link=>'',
    admin=>$CGI_URI.'/admin/admin.pl?id=8',
    threshold=>1000, # ignored
    summaryLength=>1000, #ignored
    generator=>'BSE::Generate::Article',
    thumbImage=>'',
    thumbWidth=>0,
    thumbHeight=>0,
    level=>3,
    listed=>1,
    flags=>'',
    lastModifiedBy=>'system',
    created=>"$nowDatetime",
    createdBy=>'system',
    author=>'',
    pageTitle=>'',
    force_dynamic => 0,
    cached_dynamic => 0,
    inherit_siteuser_rights => 1,
    metaDescription=>'',
    metaKeywords=>'',
    summary => '',
    menu => 0,
    titleAlias => '',
    category => '',
   },
  );

my $dbh = BSE::DB->single->dbh
  or die "Cannot connect to database: ",DBI->errstr;
my @columns = BSE::TB::Article->columns;
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
  defined $art->{linkAlias} or $art->{linkAlias} = '';
  $sth->execute(@$art{@columns})
    or die "Cannot insert row into article: ",$sth->errstr;
}
$dbh->disconnect();
