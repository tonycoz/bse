package BSE::API;
use strict;
use vars qw(@ISA @EXPORT_OK);
use BSE::Util::SQL qw(sql_datetime now_sqldatetime);
use BSE::Cfg;
require Exporter;
@ISA = qw(Exporter);
@EXPORT_OK = qw(bse_cfg bse_make_product bse_encoding);
use Carp qw(confess);

my %acticle_defaults =
  (
   titleImage => '',
   thumbImage => '',
   thumbWidth => 0,
   thumbHeight => 0,
   imagePos => 'tr',
   release => sql_datetime(time - 86_400),
   expire => '2999-12-31',
   keyword => '',
   template => 'common/default.tmpl',
   link => '', # needs to be set
   admin => '', # needs to be set
   threshold => 5,
   summaryLength => 100,
   generator => 'Generate::Article',
   # level => undef, # needs to be set
   listed => 1,
   #lastModified => undef, # needs to be set
   flags => '',
   lastModifiedBy => '',
   # created => undef # needs to be set
   createdBy => '',
   force_dynamic => 0,
   cached_dynamic => 0,
   inherit_siteuser_rights => 1,
   metaDescription => '',
   metaKeywords => '',
   summary => '',
   pageTitle => '',
   author => '',
   menu => '',
   titleAlias => '',
   linkAlias => '',
  );

my %product_defaults =
  (
   template => 'shopitem.tmpl',
   parentid => 4,
   generator => 'Generate::Product',
   wholesalePrice => 0,
   gst => 0,
   leadTime => 0,
   options => '',
   subscription_id => -1,
   subscription_period => 1,
   subscription_usage => 3,
   subscription_required => -1,
   product_code => '',
  );

sub _set_dynamic {
  my ($cfg, $article) = @_;

  if ($article->{parentid} == -1) {
    $article->{level} = 1;
  }
  else {
    require Articles;
    my $parent = Articles->getByPkey($article->{parentid})
      or confess "Invalid parent $article->{parentid}\n";
    $article->{level} = $parent->{level} + 1;
  }

  $article->{lastModified} = $article->{created} = now_sqldatetime();
}

sub _finalize_article {
  my ($cfg, $article, $editor_class) = @_;

  my $editor = $editor_class->new(cfg => $cfg, db => BSE::DB->single);

  $article->update_dynamic($cfg);
  $article->setAdmin("/cgi-bin/admin/admin.pl?id=$article->{id}");
  $article->setLink($editor->make_link($article));
  $article->save();
}

sub bse_cfg {
  my $cfg = BSE::Cfg->new;
  $cfg->entry('site', 'url')
    or confess "Could not load configuration";

  return $cfg;
}

my $order;

sub bse_make_product {
  my (%opts) = @_;

  my $cfg = delete $opts{cfg}
    or die "cfg option missing";

  require Products;

  defined $opts{title} && length $opts{title}
    or confess "Missing title option\n";
  defined $opts{body} && length $opts{body}
    or confess "Missing body option\n";
  defined $opts{retailPrice} && $opts{retailPrice} =~ /^\d+$/
    or confess "Missing or invalid retailPrice\n";

  $opts{summary} ||= $opts{title};
  $opts{description} ||= $opts{description};
  unless ($opts{displayOrder}) {
    if ($order) {
      my $now = time;
      if ($now == $order) {
	$order++;
      }
      else {
	$order = $now;
      }
    }
    else {
      $order = time;
    }
    $opts{displayOrder} = $order;
  }

  %opts =
    (
     %acticle_defaults,
     %product_defaults,
     %opts
    );

  _set_dynamic($cfg, \%opts);

  my @cols = Product->columns;
  shift @cols;
  my $product = Products->add(@opts{@cols});

  require BSE::Edit::Product;
  _finalize_article($cfg, $product, 'BSE::Edit::Product');

  return $product;
}

sub bse_encoding {
  my ($cfg) = @_;

  $cfg && $cfg->can('entry')
    or confess "bse_encoding: Missing cfg parameter\n";

  return $cfg->entry('html', 'charset', 'iso-8859-1');
}

1;
