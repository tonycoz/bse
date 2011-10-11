package BSE::Edit::Site;
use strict;

our $VERSION = "1.006";

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
     a_edit_image a_save_image a_order_images filelist fileadd fileswap filedel 
     filesave a_edit_file a_save_file a_tree a_csrfp a_article a_config);

my %more_site_actions =
  (
   a_tagshow => "req_tagshow",
   a_tags => "req_tagshow",
   a_tagrename => "req_tagrename",
   a_tagdelete => "req_tagdelete",
   a_tagcleanup => "req_tagcleanup",
  );

sub article_actions {
  my ($self) = @_;

  my %actions = $self->SUPER::article_actions();
  my %valid;
  @valid{@site_actions} = @actions{@site_actions};

  @valid{keys %more_site_actions} = values %more_site_actions;

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

sub req_tagshow {
  my ($self, $req, $article, $articles, $msg, $errors) = @_;

  my $cgi = $req->cgi;
  my $cat = $cgi->param("cat");
  my $nocat = $cgi->param("nocat");
  my @opts;
  if ($nocat) {
    push @opts, [ "=" => "cat", "" ];
    if ($cat) {
      push @opts, [ like => "val", "$cat%" ];
    }
  }
  else {
    if ($cat) {
      push @opts, [ like => "cat", "$cat%" ];
    }
  }
  my @tags = Articles->all_tags(@opts);

  if ($req->is_ajax) {
    my @json = map $_->json_data, @tags;
    if ($cgi->param("showarts")) {
      for my $i (0 .. $#tags) {
	my $tag = $tags[$i];
	my $json = $json[$i];
	$json->{articles} = [ Articles->getIdsByTag($tag) ];
      }
    }

    return $req->json_content
      (
       success => 1,
       tags => \@json,
      );
  }

  require BSE::Util::Iterate;
  my $ito = BSE::Util::Iterate::Objects->new;
  my $ita = BSE::Util::Iterate::Article->new(cfg => $req->cfg);
  my $tag;
  my %acts;
  %acts =
    (
     $ito->make_paged
     (
      single => "systag",
      plural => "systags",
      data => \@tags,
      name => "systag",
      cgi => $req->cgi,
      perpage_parm => "pp=50",
      session => $req->session,
      store => \$tag,
     ),
     $ita->make
     (
      single => "systagart",
      plural => "systagarts",
      code => sub { 
	return sort { lc $a->title cmp lc $b->title }
	  Articles->getByTag($tag);
      },
      nocache => 1,
     ),
     $self->low_edit_tags(\%acts, $req, $article, $articles, $msg, $errors),
    );
  return $req->response("admin/tags", \%acts);
}

sub req_tagrename {
  my ($self, $req, $article, $articles) = @_;

  my $cgi = $req->cgi;
  my $id = $cgi->param("tag_id");
  my $name = $cgi->param("name");

  my %errors;
  my $tag;
  unless (defined $id && $id =~ /^[0-9]+$/) {
    $errors{id} = "msg:bse/admin/edit/tags/bad_id";
  }
  unless ($errors{id}) {
    $tag = BSE::TB::Tags->getByPkey($id);
    unless ($tag) {
      $errors{tag_id} = "msg:bse/admin/edit/tags/unknown";
    }
  }

  my $error;
  unless (defined $name && BSE::TB::Tags->valid_name($name, \$error)) {
    my $msgid = "invalid_$error";
    $errors{name} = "msg:bse/admin/edit/tags/$msgid";
  }

  if ($tag && !$errors{name}) {
    my $other = Articles->getTagByName($name);
    if ($other) {
      if ($other->id != $tag->id) {
	$errors{name} = "msg:bse/admin/edit/tags/duplicate:$name";
      }
      elsif ($tag->name eq $name) {
	$errors{name} = "msg:bse/admin/edit/tags/nochange";
      }
    }
  }

  if (%errors) {
    if ($req->is_ajax) {
      return $req->field_error(\%errors);
    }
    else {
      return $self->req_tags($req, $article, $articles, undef, \%errors);
    }
  }

  my $old_name = $tag->name;
  $tag->set_name($name);
  $tag->save;

  if ($req->is_ajax) {
    return $req->json_content
      (
       success => 1,
       tag => $tag->json_data,
      );
  }

  $req->flash("msg:bse/admin/edit/tags/saved", [ $old_name, $tag->name ]);
  return $self->refresh($article, $cgi, undef, undef, "&a_tags=1");
}

sub req_tagdelete {
  my ($self, $req, $article, $articles) = @_;

  my $cgi = $req->cgi;
  my $id = $cgi->param("tag_id");

  my %errors;
  my $tag;
  unless (defined $id && $id =~ /^[0-9]+$/) {
    $errors{id} = "msg:bse/admin/edit/tags/bad_id";
  }
  unless ($errors{id}) {
    $tag = BSE::TB::Tags->getByPkey($id);
    unless ($tag) {
      $errors{tag_id} = "msg:bse/admin/edit/tags/unknown";
    }
  }

  if (%errors) {
    if ($req->is_ajax) {
      return $req->field_error(\%errors);
    }
    else {
      return $self->req_tags($req, $article, $articles, undef, \%errors);
    }
  }

  my $name = $tag->name;

  $tag->remove;

  if ($req->is_ajax) {
    return $req->json_content
      (
       success => 1,
      );
  }

  $req->flash("msg:bse/admin/edit/tags/removed", [ $name ]);
  return $self->refresh($article, $cgi, undef, undef, "&a_tags=1");
}

sub req_tagcleanup {
  my ($self, $req, $article, $articles) = @_;

  require BSE::TB::Tags;
  my $count = 0 + BSE::TB::Tags->cleanup();

  if ($req->is_ajax) {
    return $req->json_content
      (
       success => 1,
       count => $count,
      );
  }

  $req->flash("msg:bse/admin/edit/tags/cleanup", [ $count ]);
  return $self->refresh($article, $req->cgi, undef, undef, "&a_tags=1");
}

1;
