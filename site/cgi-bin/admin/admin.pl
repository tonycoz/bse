#!/usr/bin/perl -w
# -d:ptkdb
#BEGIN { $ENV{DISPLAY} = '192.168.32.97:0.0' }
use strict;
use FindBin;
use CGI::Carp 'fatalsToBrowser';
use CGI qw(:standard);
#use Carp 'verbose'; # remove the 'verbose' in production
use lib "$FindBin::Bin/../modules";
use Articles;

my $id = param('id');
defined $id or $id = 1;
my $admin = 1;
$admin = param('admin') if defined param('admin');

my $articles = Articles->new;

my $article = $articles->getByPkey($id)
  or die "Cannot find article ",$id;

eval "use $article->{generator}";
die $@ if $@;
my $generator = $article->{generator}->new(admin=>$admin, articles=>$articles);

print "Content-Type: text/html\n\n";
print $generator->generate($article, $articles);

