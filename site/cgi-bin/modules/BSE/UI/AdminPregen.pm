package BSE::UI::AdminPregen;
use strict;
use base qw(BSE::UI::AdminDispatch);
use BSE::Util::Iterate;
use BSE::Util::Tags qw(tag_hash);

my %actions =
  (
   list => "",
   show => "",
   display => "",
  );

sub actions { \%actions }

sub rights { \%actions }

sub default_action { "list" }

sub req_list {
  my ($self, $req) = @_;

  my %entries = $req->cfg->entries('pregenerate');

  my @names = sort keys %entries;

  my @templates = map
    {;
     my ($type, $src) = split /,/, $entries{$_}, 2;
     +{
       id => $_,
       type => $type,
       source => $src,
      };
     } @names;
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
    );

  return $req->response("admin/pregen/index", \%acts);
}

sub req_show {
  my ($self, $req) = @_;

  my $id = $req->cgi->param("template");
  $id
    or return $self->req_list($req, { template => "No pregen template" });
  my $entry = $req->cfg->entry("pregenerate", $id)
    or return $self->req_list($req, { template => "Unknown pregen template $id" });

  my %template = ( id => $id );
  @template{qw/type source/} = split /,/, $entry, 2;

  my %acts =
    (
     $req->admin_tags,
     template => [ \&tag_hash, \%template ],
    );

  return $req->response("admin/pregen/show", \%acts);
}

sub req_display {
  my ($self, $req) = @_;

  my $cfg = $req->cfg;
  my $id = $req->cgi->param("template");
  $id
    or return $self->req_list($req, { template => "No pregen template" });
  my $entry = $cfg->entry("pregenerate", $id)
    or return $self->req_list($req, { template => "Unknown pregen template $id" });

  require Generate::Article;
  my ($presets, $input) = split ',', $entry, 2;
  my $section = "$presets settings";
  my %article = map { $_, '' } Article->columns;
  $article{displayOrder} = 1;
  $article{id} = -5;
  $article{parentid} = -1;
  $article{link} = $cfg->entryErr('site', 'url');
  for my $field (Article->columns) {
    if ($cfg->entry($section, $field)) {
      $article{$field} = $cfg->entryVar($section, $field);
    }
  }
  # by default all of these are handled as dynamic, but it can be 
  # overidden, eg. the error template
  my $is_extras = $presets eq 'extras';
  my $dynamic = $cfg->entry($section, 'dynamic', !$is_extras);
  my %acts;
  my $gen = Generate::Article->new
    (
     cfg=>$cfg,
     top=>\%article, 
     force_dynamic => $dynamic,
     admin => 1,
     request => $req,
     articles => "Articles",
    );
  %acts = $gen->baseActs("Articles", \%acts, \%article);
  my $oldurl = $acts{url};
  $acts{url} =
    sub {
      my $value = $oldurl->(@_);
      $value =~ /^<:/ and return $value;
      unless ($value =~ /^\w+:/) {
	# put in the base site url
	$value = $cfg->entryErr('site', 'url').$value;
      }
      return $value;
    };
  my $content = BSE::Template->get_page($input, $cfg, \%acts);

  return
    {
     content => $content,
     type => BSE::Template->html_type($req->cfg),
    };
}

1;
