package BSE::Edit::Catalog;
use strict;
use base 'BSE::Edit::Article';
use BSE::Util::HTML;
use BSE::Util::Tags qw(tag_article);
use constant CATALOG_CUSTOM_FIELDS_CFG => "catalog custom fields";

our $VERSION = "1.004";

sub base_template_dirs {
  return ( "catalog" );
}

sub extra_templates {
  my ($self, $article) = @_;

  my @extras = $self->SUPER::extra_templates($article);
  my $basedir = $self->{cfg}->entryVar('paths', 'templates');
  push @extras, 'catalog.tmpl' if -f "$basedir/catalog.tmpl";

  return @extras;
}

#  sub low_edit_tags {
#    my ($self, $acts, $req, $article, $articles, $msg) = @_;

#    return 
#      (
#       $self->SUPER::low_edit_tags($acts, $req, $article, $articles, $msg),
#      );
#  }

sub edit_template { 
  my ($self, $article, $cgi) = @_;

  my $base = 'catalog';
  my $t = $cgi->param('_t');
  if ($t && $t =~ /^\w+$/) {
    $base = $t;
  }
  return $self->{cfg}->entry('admin templates', $base, 
			     "admin/edit_$base");
}

sub generator { "BSE::Generate::Catalog" }

sub validate_parent {
  my ($self, $data, $articles, $parent, $rmsg) = @_;

  my $shopid = $self->{cfg}->entryErr('articles', 'shop');
  unless ($parent && 
	  ($parent->{id} == $shopid 
	   || $parent->{generator} eq 'BSE::Generate::Catalog')) {
    $$rmsg = "Catalogs must be in the shop";
    return;
  }

  return $self->SUPER::validate_parent($data, $articles, $parent, $rmsg);
}

sub possible_parents {
  my ($self, $article, $articles) = @_;

  my %labels;
  my @values;

  my $shopid = $self->{cfg}->entryErr('articles', 'shop');
  # the parents of a catalog can be other catalogs or the shop
  my $shop = $articles->getByPkey($shopid);
  my @work = [ $shopid, $shop->{title} ];
  while (@work) {
    my ($id, $title) = @{pop @work};
    if (!$article->{id} || $article->{id} != $id) {
      push(@values, $id);
      $labels{$id} = $title;
      push @work, map [ $_->{id}, $title.' / '.$_->{title} ],
	sort { $b->{displayOrder} <=> $a->{displayOrder} }
	  grep $_->{generator} eq 'BSE::Generate::Catalog', 
	    $articles->getBy(parentid=>$id);
    }
  }

  return (\@values, \%labels);
}

sub default_link_path {
  my ($self, $article) = @_;

  $self->{cfg}->entry('uri', 'shop', '/shop');
}

sub make_link {
  my ($self, $article) = @_;

  $article->is_linked
    or return "";

# Modified by adrian
  my $urlbase = '';
  if ($self->{cfg}->entry('shop', 'secureurl_articles', 1)) {
    $urlbase = $self->{cfg}->entryVar('site', 'secureurl');
  }
# end adrian

  if ($article->is_dynamic) {
    return "$urlbase/cgi-bin/page.pl?page=$article->{id}&title=".escape_uri($article->{title});
  }

  my $shop_uri = $self->link_path($article);
  return $urlbase.$shop_uri."/shop$article->{id}.html";
}

sub child_types {
  return qw(BSE::Edit::Product BSE::Edit::Seminar BSE::Edit::Catalog);
}

sub shop_article { 1 }

sub default_template {
  my ($self, $article, $cfg, $templates) = @_;

  my $template = $cfg->entry('catalogs', 'template');
  return $template
    if $template && grep $_ eq $template, @$templates;

  return $self->SUPER::default_template($article, $cfg, $templates);
}

sub flag_sections {
  my ($self) = @_;

  return ( 'catalog flags', $self->SUPER::flag_sections );
}

sub type_default_value {
  my ($self, $req, $col) = @_;

  my $value = $req->cfg->entry('catalog defaults', $col);
  defined $value and return $value;

  return $self->SUPER::type_default_value($req, $col);
}

sub custom_fields {
  my ($self) = @_;

  my $custom = $self->SUPER::custom_fields();

  require DevHelp::Validate;
  DevHelp::Validate->import;
  return DevHelp::Validate::dh_configure_fields
    (
     $custom,
     $self->cfg,
     CATALOG_CUSTOM_FIELDS_CFG,
     BSE::DB->single->dbh,
    );
}

1;

