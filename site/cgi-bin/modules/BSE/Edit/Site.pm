package BSE::Edit::Site;
use strict;

use base 'BSE::Edit::Article';

sub edit_sections {
  my ($self, $req, $articles, $msg) = @_;

  BSE::Permissions->check_logon($req)
    or return BSE::Template->get_refresh($req->url('logon'), $req->cfg);

  my %article;
  my @cols = Article->columns;
  @article{@cols} = ('') x @cols;
  $article{id} = '-1';
  $article{parentid} = -1;
  $article{level} = 0;
  $article{body} = '';
  $article{listed} = 0;
  $article{generator} = $self->generator;
  $article{flags} = '';

  #return $self->low_edit_form($req, \%article, $articles, $msg);
  return $self->article_dispatch($req, \%article, $articles);
}

my @site_actions =
  qw(edit artimg process addimg removeimg moveimgup moveimgdown a_thumb);

sub article_actions {
  my ($self) = @_;

  my %actions = $self->SUPER::article_actions();
  my %valid;
  @valid{@site_actions} = @actions{@site_actions};

  %valid;
}

sub get_images {
  my ($self, $article) = @_;

  require Images;

  Images->getBy(articleId => -1);
}

sub validate_image_name {
  my ($self, $name, $rmsg) = @_;

  length $name and return 1;
  
  $$rmsg = "Name must be supplied for global images";

  return 0;
}

1;
