#!/usr/bin/perl -w
# -d:ptkdb
#BEGIN { $ENV{DISPLAY} = '192.168.32.97:0.0' }
use strict;
use FindBin;
use CGI::Carp 'fatalsToBrowser';
#use Carp 'verbose'; # remove the 'verbose' in production
use lib "$FindBin::Bin/../modules";
use Articles;
use BSE::Request;
use Util 'refresh_to';

my $req = BSE::Request->new;
my $cfg = $req->cfg;

if ($req->check_admin_logon()) {
  my $cgi = $req->cgi;
  my $id = $cgi->param('id');
  defined $id or $id = 1;
  my $admin = 1;
  $admin = $cgi->param('admin') if defined $cgi->param('admin');
  
  #my $articles = Articles->new;
  my $articles = 'Articles';
  
  my $article = $articles->getByPkey($id)
    or die "Cannot find article ",$id;
  
  eval "use $article->{generator}";
  die $@ if $@;
  my $generator = $article->{generator}->new(admin=>$admin, articles=>$articles, cfg=>$cfg, request=>$req);
  
  print "Content-Type: text/html\n\n";
  print $generator->generate($article, $articles);
}
else {
  my $urlbase = $cfg->entryErr('site', 'url');
  refresh_to("$urlbase/cgi-bin/admin/logon.pl");
}
