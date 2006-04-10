#!/usr/bin/perl -w
use strict;

print "Content-Type: text/html\n\n";

print <<EOS;
<html><head><title>BSE Module Check</title></head>
<body>
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
     }
   },
   {
    name => "Securepay XML",
    modules =>
    {
     'XML::Simple' => 0,
     'LWP::UserAgent' => 0,
     'Crypt::SSLeay' => 0,
    },
   },
   {
    name => "Nport",
    modules => 
    {
     'MIME::Lite' => 0,
     'Time::HiRes' => 0,
     'Date::Calc' => 0,
    },
   },
   {
    name => "Optional",
    modules =>
    {
     'Imager' => 0.44,
     'Log::Agent' => 0,
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
     FCGI => 0,
     'CGI::Fast' => 0,
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
  print "<h1>$sect->{name}</h1>\n";
  for my $module (sort keys %{$sect->{modules}}) {
    my $use = "use $module";
    if ($sect->{modules}{$module}) {
      $use .= " " . $sect->{modules}{$module};
    }
    $use .= ';';
    eval $use;
    if ($@) {
      my $msg = escape_html($@);
      $msg =~ s!\n!<br />!g;
      print "<p>Error loading $module: $msg</p>\n";
    }
    else {
      print "<p>$module loaded successfully\n</p>";
    }
  }
}

print "</body></html>\n";

my %escape;

BEGIN {
  %escape = ( '>' => '&gt;', '<' => '&lt;', '&' => '&amp;' );
}

sub escape_html {
  my ($str) = @_;

  $str =~ s/([<>&])/$escape{$1}/g;

  $str;
}
