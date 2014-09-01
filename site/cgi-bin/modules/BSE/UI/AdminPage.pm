package BSE::UI::AdminPage;
use strict;
use BSE::TB::Articles;
use BSE::Util::HTML qw(escape_uri);
use BSE::UI::AdminDispatch;
use BSE::TB::Articles;
our @ISA = qw(BSE::UI::AdminDispatch);

our $VERSION = "1.001";

my %actions =
  (
   adminpage => "",
   warnings => "",
  );

sub actions {
  \%actions
}

sub rights {
  \%actions
}

sub default_action { 'adminpage' }

sub req_adminpage {
  my ($self, $req) = @_;

  my $cgi = $req->cgi;
  my $id = $cgi->param('id');
  defined $id or $id = 1;
  my $admin = 1;
  $admin = $cgi->param('admin') if defined $cgi->param('admin');
  my $admin_links = $admin;
  $admin_links = $cgi->param('admin_links')
    if defined $cgi->param('admin_links');
  
  #my $articles = BSE::TB::Articles->new;
  my $articles = 'BSE::TB::Articles';
  
  my $article;
  $article = $articles->getByPkey($id) if $id =~ /^\d+$/;

  if ($article) {
    local *OLDERR = *STDERR;
    local *STDERR;

    my $cap = tie *STDERR, "BSE::UI::AdminPage::CaptureErrors", \*OLDERR;

    eval "use $article->{generator}";
    die $@ if $@;
    my $generator = $article->{generator}->new
      (
       admin=>$admin,
       admin_links => $admin_links,
       articles=>$articles,
       cfg=>$req->cfg,
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

      $req->cache_set("page_warnings-".$article->id => [ $cap->data ]);

      return $result;
    }
    else {
      my $type = BSE::Template->html_type($req->cfg);
      my $page = $generator->generate($article, $articles);
      if ($req->utf8) {
	require Encode;
	$page = Encode::encode($req->charset, $page);
      }

      $req->cache_set("page_warnings-".$article->id => [ $cap->data ]);
      return
	{
	 content => $page,
	 type => $type,
	};
    }
  }
  else {
    # display a message on the admin menu
    $req->flash_error("No such article '$id'");
    return $req->get_refresh($req->url("menu"));
  }
}

sub req_warnings {
  my ($self, $req) = @_;

  my $id = $req->cgi->param("id");

  defined $id && $id =~ /^[0-9]+$/
    or return $req->field_error($req, { id => "id must be numeric" });

  my $warnings = $req->cache_get("page_warnings-$id") || [];

  return $req->json_content
    ({
      success => 1,
      warnings => $warnings,
     });
}

package BSE::UI::AdminPage::CaptureErrors;
use base 'Tie::Handle';

sub TIEHANDLE {
  my ($class, $handle) = @_;

  return bless { data => "", old => $handle }, $class;
}

sub WRITE {
  my ($self, $buf, $len, $offset) = @_;

  $self->{data} .= substr($buf, $offset, $len);
  print {$self->{old}} substr($buf, $offset, $len);

  1;
}

sub data {
  return split /\n/, $_[0]{data};
}

1;
