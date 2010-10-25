#!/usr/bin/perl -w
# -d:ptkdb
BEGIN { $ENV{DISPLAY} = '192.168.32.54:0.0' }
use strict;
use FindBin;
#use CGI::Carp 'fatalsToBrowser';
use Carp 'verbose'; # remove the 'verbose' in production
use Carp 'confess';
use lib "$FindBin::Bin/../modules";
use Articles;
use BSE::Request;
use BSE::WebUtil 'refresh_to_admin';

$SIG{__DIE__} = sub { confess @_ };

my $req = BSE::Request->new;
my $cfg = $req->cfg;

if ($req->check_admin_logon()) {
  my $cgi = $req->cgi;
  my $id = $cgi->param('id');
  defined $id or $id = 1;
  my $admin = 1;
  $admin = $cgi->param('admin') if defined $cgi->param('admin');
  my $admin_links = $admin;
  $admin_links = $cgi->param('admin_links')
    if defined $cgi->param('admin_links');
  
  #my $articles = Articles->new;
  my $articles = 'Articles';
  
  my $article;
  $article = $articles->getByPkey($id) if $id =~ /^\d+$/;

  if ($article) {
    eval "use $article->{generator}";
    die $@ if $@;
    my $generator = $article->{generator}->new
      (
       admin=>$admin,
       admin_links => $admin_links,
       articles=>$articles,
       cfg=>$cfg,
       request=>$req,
       top=>$article
      );

    if ($article->is_dynamic) {
      my $content = $generator->generate($article, $articles);
      (my $dyn_gen_class = $article->{generator}) =~ s/.*\W//;
      $dyn_gen_class = "BSE::Dynamic::".$dyn_gen_class;
      (my $dyn_gen_file = $dyn_gen_class . ".pm") =~ s!::!/!g;
      require $dyn_gen_file;
      my $dyn_gen = $dyn_gen_class->new
	(
	 $req,
	 admin => $admin,
	 admin_links => $admin_links,
	);
      $article = $dyn_gen->get_real_article($article);
      my $result = $dyn_gen->generate($article, $content);
      BSE::Template->output_result($req, $result);
    }
    else {
      my $type = BSE::Template->html_type($req->cfg);
      print "Content-Type: $type\n\n";
      my $page = $generator->generate($article, $articles);
      if ($req->utf8) {
	require Encode;
	$page = Encode::encode($req->charset, $page);
      }
      print $page;
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
