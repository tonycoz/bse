#!/usr/bin/perl -w
use strict;

print "Content-Type: text/html\n\n";

print <<EOS;
<?xml version="1.0" encoding="utf-8"?>
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN"
   "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd" >
<html xmlns="http://www.w3.org/1999/xhtml">
  <head>
    <title>BSE Module Check</title>
    <link rel="stylesheet" href="/css/admin.css" />
<style type="text/css">
li.error {
  font-weight: bold;
}
</style>
  </head>
<body>
<h1>BSE Module Check</h1>

<p>| <a href="/cgi-bin/admin/menu.pl">Admin Menu</a> |</p>
<div id="bse_modules">
EOS

my @base_check =
  (
   { name => "Base requirements",
     modules => 
     { 
      'DBI' => 0, 
      'DBD::mysql' => 0, 
      'Digest::MD5' => 0,
      'Apache::Session' => 0,
      'Storable' => 0,
      'HTML::Parser' => 0,
      'URI::Escape' => 0,
      'HTML::Entities' => 0,
      'Image::Size' => 0,
      'JSON' => 0,
      'MIME::Lite' => 0,
      'Date::Format' => 0,
      'Data::UUID' => '1.148',
      'File::Slurp' => 0,
      'Time::HiRes' => 0,
      'WWW::Mechanize' => 0,
      'Net::IP' => 0,
      'Data::Password::Entropy' => 0,
     }
   },
   {
    name => "Securepay XML",
    modules =>
    {
     'XML::Simple' => 0,
     'LWP::UserAgent' => 0,
     'LWP::Protocol::https' => 6.02,
     'Mozilla::CA' => 0,
    },
   },
   {
    name => "EWay payments",
    modules =>
    {
     'XML::LibXML' => 0,
     'LWP::UserAgent' => 0,
     'LWP::Protocol::https' => 6.02,
     'Mozilla::CA' => 0,
    },
   },
   {
    name => "Courier modules",
    modules =>
    {
     'LWP::UserAgent' => 0,
    },
   },
   {
    name => "Fastway Couriers",
    modules =>
    {
     'XML::Parser' => 0,
    },
   },
   {
    name => "Optional",
    modules =>
    {
     'Imager' => 0.62,
     'Imager::Filter::Sepia' => 0,
     'Log::Agent' => 0,
     'Net::Amazon::S3' => 0,
     'Captcha::reCAPTCHA' => 0,
     'FLV::Info' => 0,
     'DBM::Deep' => 2,
     'CSS::Inliner' => 3042,
     'DBM::Deep' => 0,
     'Spreadsheet::ParseExcel' => 0.55,
     'Text::CSV' => 0,
    },
   },
   {
    name => 'mod-perl 1.x support',
    modules =>
    {
     'Apache::Request' => 0,
    },
   },
   {
    name => 'FastCGI support',
    modules =>
    {
     'FCGI' => 0,
     'CGI::Fast' => 0,
    },
   },
   {
    name => "Caching - one of the following",
    modules =>
    {
     "CHI" => 0.23,
     "Cache" => 2.00,
     "Cache::Memcached::Fast" => 0.17,
    },
   },
   {
    name => "Online HTML validation",
    modules =>
    {
     'WebService::Validator::HTML::W3C' => 0,
    },
   },
   {
    name => "Following should fail\n",
    modules =>
    {
     'ShouldNotLoad' => 0,
    },
   },
  );

for my $sect (@base_check) {
  print qq(<div class="category"><h2>$sect->{name}</h2><ul>\n);
  for my $module (sort keys %{$sect->{modules}}) {
    my $use = "use $module";
    if ($sect->{modules}{$module}) {
      $use .= " " . $sect->{modules}{$module};
    }
    $use .= ';';
    eval $use;
    if ($@) {
      my $msg = escape_html($@);
      (my $mod_file = $module . ".pm") =~ s(::)(/)g;
      if ($msg =~ /^Can't locate \Q$mod_file\E in \@INC /) {
	$msg = "Not found";
      }
      $msg =~ s!\n!<br />!g;
      print "<li class=\"error\">$module: $msg</li>\n";
    }
    else {
      print "<li>$module: loaded successfully\n</li>";
    }
  }
  print "</ul></div>\n";
}

print "</div></body></html>\n";

my %escape;

BEGIN {
  %escape = ( '>' => '&gt;', '<' => '&lt;', '&' => '&amp;' );
}

sub escape_html {
  my ($str) = @_;

  $str =~ s/([<>&])/$escape{$1}/g;

  $str;
}
