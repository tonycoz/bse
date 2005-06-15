package BSE::Edit::Seminar;
use strict;
use base 'BSE::Edit::Product';
use BSE::TB::Seminars;
use BSE::Util::Tags qw(tag_hash tag_hash_mbcs);

sub base_template_dirs {
  return ( "seminar" );
}

sub edit_template { 
  my ($self, $article, $cgi) = @_;

  my $base = 'seminar';
  my $t = $cgi->param('_t');
  if ($t && $t =~ /^\w+$/) {
    $base = $t;
  }
  return $self->{cfg}->entry('admin templates', $base, 
			     "admin/edit_$base");
}

sub generator { "BSE::Generate::Seminar" }

sub default_template {
  my ($self, $article, $cfg, $templates) = @_;

  my $template = $cfg->entry('seminars', 'template');
  return $template
    if $template && grep $_ eq $template, @$templates;

  return $self->SUPER::default_template($article, $cfg, $templates);
}

sub flag_sections {
  my ($self) = @_;

  return ( 'seminar flags', $self->SUPER::flag_sections );
}

sub type_default_value {
  my ($self, $req, $col) = @_;

  my $value = $req->cfg->entry('seminar defaults', $col);
  defined $value and return $value;

  return $self->SUPER::type_default_value($req, $col);
}

sub add_template { 
  my ($self, $article, $cgi) = @_;

  return $self->{cfg}->entry('admin templates', 'add_seminar', 
			     'admin/edit_seminar');
}

sub table_object {
  my ($self, $articles) = @_;

  'BSE::TB::Seminars';
}

sub low_edit_tags {
  my ($self, $acts, $req, $article, $articles, $msg, $errors) = @_;

  my $cfg = $req->cfg;
  my $mbcs = $cfg->entry('html', 'mbcs', 0);
  my $tag_hash = $mbcs ? \&tag_hash_mbcs : \&tag_hash;
  my $it = BSE::Util::Iterate->new;
  return 
    (
     seminar => [ $tag_hash, $article ],
     $self->SUPER::low_edit_tags($acts, $req, $article, $articles, $msg,
				$errors),
    );
}

sub get_article {
  my ($self, $articles, $article) = @_;

  return BSE::TB::Seminars->getByPkey($article->{id});
}

my %defaults =
  (
   duration => 60,
  );

sub default_value {
  my ($self, $req, $article, $col) = @_;

  my $value = $self->SUPER::default_value($req, $article, $col);
  defined $value and return $value;

  exists $defaults{$col} and return $defaults{$col};

  return;
}

sub _fill_seminar_data {
  my ($self, $req, $data, $src) = @_;

  if (exists $src->{duration}) {
    $data->{duration} = $src->{duration};
  }
}

sub fill_new_data {
  my ($self, $req, $data, $articles) = @_;

  $self->_fill_seminar_data($req, $data, $data);

  return $self->SUPER::fill_new_data($req, $data, $articles);
}

sub fill_old_data {
  my ($self, $req, $article, $src) = @_;

  $self->_fill_seminar_data($req, $article, $src);

  return $self->SUPER::fill_old_data($req, $article, $src);
}

sub _validate_common {
  my ($self, $data, $articles, $errors) = @_;

  my $duration = $data->{duration};
  if (defined $duration && $duration !~ /^\d+\s*$/) {
    $errors->{duration} = "Duration invalid";
  }

  return $self->SUPER::_validate_common($data, $articles, $errors);
}

1;

