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
  qw(edit artimg process addimg removeimg moveimgup moveimgdown a_thumb
     a_edit_image a_save_image filelist fileadd fileswap filedel 
     filesave a_edit_file a_save_file);

sub article_actions {
  my ($self) = @_;

  my %actions = $self->SUPER::article_actions();
  my %valid;
  @valid{@site_actions} = @actions{@site_actions};

  %valid;
}

sub get_images {
  my ($self, $article) = @_;

  require BSE::TB::Images;

  return BSE::TB::Images->getBy(articleId => -1);
}

sub get_files {
  my ($self, $article) = @_;

  Articles->global_files;
}

sub validate_image_name {
  my ($self, $name, $rmsg) = @_;

  length $name and return 1;
  
  $$rmsg = "Name must be supplied for global images";

  return 0;
}

1;
