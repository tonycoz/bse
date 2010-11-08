package BSE::Util::ContentType;
use strict;
require Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(content_type);

our $VERSION = "1.000";

my %types =
  (
   qw(
   bash text/plain
   css  text/css
   csv  text/plain
   diff text/plain
   htm  text/html
   html text/html
   ics  text/calendar
   patch text/plain
   pl   text/plain
   pm   text/plain
   pod  text/plain
   py   text/plain
   sgm  text/sgml
   sgml text/sgml
   sh   text/plain
   tcsh text/plain
   text text/plain
   tsv  text/tab-separated-values
   txt  text/plain
   vcf  text/x-vcard
   vcs  text/x-vcalendar
   xml  text/xml
   zsh  text/plain
   bmp  image/bmp 
   gif  image/gif
   jp2  image/jpeg2000
   jpeg image/jpeg
   jpg  image/jpeg   
   pct  image/pict 
   pict image/pict
   png  image/png
   tif  image/tiff
   tiff image/tiff
   dcr  application/x-director
   dir  application/x-director
   doc  application/msword
   dxr  application/x-director
   eps  application/postscript
   fla  application/x-shockwave-flash
   flv  application/x-shockwave-flash
   gz   application/gzip
   hqx  application/mac-binhex40
   js   application/x-javascript
   lzh  application/x-lzh
   pdf  application/pdf
   pps  application/ms-powerpoint
   ppt  application/ms-powerpoint
   ps   application/postscript
   rtf  application/rtf
   sit  application/x-stuffit
   swf  application/x-shockwave-flash
   tar  application/x-tar
   tgz  application/gzip
   xls  application/ms-excel
   Z    application/x-compress
   zip  application/zip
   asf  video/x-ms-asf
   avi  video/avi
   flc  video/flc
   moov video/quicktime
   mov  video/quicktime
   mp4  video/mp4
   mpeg video/mpeg
   mpg  video/mpeg
   wmv  video/x-ms-wmv
   3gp  video/3gpp
   aa   audio/audible
   aif  audio/aiff
   aiff audio/aiff
   m4a  audio/m4a
   mid  audio/midi
   mp2  audio/x-mpeg
   mp3  audio/x-mpeg
   ra   audio/x-realaudio
   ram  audio/x-pn-realaudio
   rm   audio/vnd.rm-realmedia
   swa  audio/mp3
   wav  audio/wav
   wma  audio/x-ms-wma
   )
  );

sub content_type {
  my ($cfg, $filename) = @_;

  if ($filename =~ /\.(\w+)$/) {
    my $ext = lc $1;
    my $type = $types{$ext};
    unless ($type) {
      $type = $cfg->entry('extensions', $ext)
	|| $cfg->entry('extensions', ".$ext")
	  || "application/octet-stream";
    }
    
    return $type;
  }
  else {
    return "application/octet-stream";
  }
}

