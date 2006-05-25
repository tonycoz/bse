#!/usr/bin/perl -w
use strict;
use CGI;

my $start = time;
my $step = 5;

my $q = CGI->new;

my $max = $q->param('max') || 300;

++$|;
print "Content-Type: text/html\n\n";

print <<EOS;
<html><head><title>BSE Script Timeout Check</title></head>
<body>
EOS

my $elapsed = time - $start;
do {
  my $sleep = $max - $elapsed;
  $sleep > $step and $sleep = $step;
  sleep $sleep;
  $elapsed = time - $start;
  print "<p>$elapsed seconds elapsed</p>\n";
} while ($elapsed < $max);

print <<EOS;
</body>
</html>
EOS
