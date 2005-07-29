#!/usr/bin/perl -w
# -d:ptkdb
#BEGIN { $ENV{DISPLAY} = '192.168.32.15:0.0' }
use strict;
use FindBin;
use CGI::Carp 'fatalsToBrowser';
#use Carp 'verbose'; # remove the 'verbose' in production
use lib "$FindBin::Bin/../modules";
use Articles;
use BSE::Request;
use BSE::WebUtil 'refresh_to_admin';

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
  
  my $article;
  $article = $articles->getByPkey($id) if $id =~ /^\d+$/;

  if ($article) {
    eval "use $article->{generator}";
    die $@ if $@;
    my $generator = $article->{generator}
      ->new(admin=>$admin, articles=>$articles, cfg=>$cfg, request=>$req, 
	    top=>$article);

    if ($article->is_dynamic) {
      my $content = $generator->generate($article, $articles);
      (my $dyn_gen_class = $article->{generator}) =~ s/.*\W//;
      $dyn_gen_class = "BSE::Dynamic::".$dyn_gen_class;
      (my $dyn_gen_file = $dyn_gen_class . ".pm") =~ s!::!/!g;
      require $dyn_gen_file;
      my $dyn_gen = $dyn_gen_class->new($req);
      $article = $dyn_gen->get_real_article($article);
      my $result = $dyn_gen->generate($article, $content);
      BSE::Template->output_result($req, $result);
    }
    else {
      print "Content-Type: text/html\n\n";
      print $generator->generate($article, $articles);
    }
  }
  else {
    # display a message on the admin menu
    refresh_to_admin($req->cfg,
		     $req->url(menu =>{ 'm' => "No such article '${id}'"} ));
  }
}
else {
  refresh_to_admin($cfg, "/cgi-bin/admin/logon.pl");
}
