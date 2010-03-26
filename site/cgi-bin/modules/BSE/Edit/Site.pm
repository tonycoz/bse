package BSE::Edit::Site;
use strict;

use base 'BSE::Edit::Article';
use BSE::TB::Site;

sub edit_sections {
  my ($self, $req, $articles, $msg) = @_;

  BSE::Permissions->check_logon($req)
    or return $self->not_logged_on($req);

  my $article = BSE::TB::Site->new;

  return $self->article_dispatch($req, $article, $articles);
}

my @site_actions =
  qw(edit artimg process addimg removeimg moveimgup moveimgdown a_thumb
     a_edit_image a_save_image filelist fileadd fileswap filedel 
     filesave a_edit_file a_save_file a_tree a_csrfp a_article);

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
