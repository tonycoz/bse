package BSE::UI::AdminPregen;
use strict;
use base qw(BSE::UI::AdminDispatch);
use BSE::Util::Iterate;
use BSE::Util::Tags qw(tag_hash);
use BSE::Regen qw(pregenerate_list content_one_extra response_one_extra);

our $VERSION = "1.002";

my %actions =
  (
   list => "bse_pregen_view",
   show => "bse_pregen_view",
   display => "bse_pregen_view",
  );

sub actions { \%actions }

sub rights { \%actions }

sub default_action { "list" }

sub req_list {
  my ($self, $req, $errors) = @_;

  my @templates = pregenerate_list($req->cfg);
  # back compat
  for my $template (@templates) {
    $template->{id} = $template->{name};
  }
  my $message = $req->message($errors);
  my $it = BSE::Util::Iterate->new;
  my %acts =
    (
     $req->admin_tags,
     $it->make
     (
      single => "template",
      plural => "templates",
      data => \@templates,
     ),
     message => $message,
    );

  return $req->response("admin/pregen/index", \%acts);
}

sub req_show {
  my ($self, $req) = @_;

  my $id = $req->cgi->param("template");
  $id
    or return $self->req_list($req, { template => "No pregen template" });
  my ($entry) = grep $_->{name} eq $id, pregenerate_list($req->cfg)
    or return $self->req_list($req, { template => "Unknown pregen template $id" });

  $entry->{id} = $entry->{name};

  my $message = $req->message();
  my %acts =
    (
     $req->admin_tags,
     template => [ \&tag_hash, $entry ],
     message => $message,
    );

  return $req->response("admin/pregen/show", \%acts);
}

sub req_display {
  my ($self, $req) = @_;

  my $cfg = $req->cfg;
  my $id = $req->cgi->param("template");
  $id
    or return $self->req_list($req, { template => "No pregen template" });
  my ($entry) = grep $_->{name} eq $id, pregenerate_list($req->cfg)
    or return $self->req_list($req, { template => "Unknown pregen template $id" });

  if ($entry->{dynamic}) {
    my ($content, $article) = content_one_extra("Articles", $entry);

    require BSE::Dynamic::Article;
    my $dyngen = BSE::Dynamic::Article->new($req);
    return $dyngen->generate($article, $content);
  }
  else {
    return response_one_extra("Articles", $entry);
  }
}

1;
