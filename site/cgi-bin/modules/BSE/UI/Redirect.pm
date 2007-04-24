package BSE::UI::Redirect;
use strict;
use base qw(BSE::UI::Dispatch);
use Digest::MD5 qw(md5_hex);
use DevHelp::HTML;

my %actions =
  (
   redir => 1,
   doit => 1,
   cancel => 1,
  );

sub actions { \%actions };

sub default_action { 'redir' }

sub req_redir {
  my ($self, $req) = @_;

  my $cgi = $req->cgi;
  my $url = $cgi->param('url')
    or return $self->error($req, "No url supplied");
  my $text = $cgi->param('title') || $url;
  my $hash = $cgi->param('h')
    or return $self->error($req, "No hash supplied");
  my $salt = $req->cfg->entry('html', 'redirect_salt', '');
  my $gen_hash = substr(md5_hex($url, $text, $salt), 0, 16);

  $hash eq $gen_hash
    or return $self->error($req, "Invalid hash supplied");

  my $url_hash = substr(md5_hex($url, $salt), 0, 16);
  my $referer = $ENV{HTTP_REFERER};
  my $refer_hash = substr(md5_hex($referer, $salt), 0, 16);

  my %acts =
    (
     $req->dyn_user_tags(),
     targeturl => escape_html($url),
     text => escape_html($text),
     referer => escape_html($referer),
     urlhash => $url_hash,
     referhash => $refer_hash,
     message => '',
    );

  return $req->dyn_response('user/redirect', \%acts);
}

sub req_doit {
  my ($class, $req) = @_;

  my $cgi = $req->cgi;
  my $url = $cgi->param('targeturl');
  my $hash = $cgi->param('urlhash');
  my $salt = $req->cfg->entry('html', 'redirect_salt', '');
  my $gen_hash = substr(md5_hex($url, $salt), 0, 16);
  $hash eq $gen_hash
    or return $class->error($req, "Invalid hash supplied");

  return BSE::Template->get_refresh($url, $req->cfg);
}

sub req_cancel {
  my ($class, $req) = @_;

  my $cgi = $req->cgi;
  my $url = $cgi->param('referer');
  my $hash = $cgi->param('referhash');
  my $salt = $req->cfg->entry('html', 'redirect_salt', '');
  my $gen_hash = substr(md5_hex($url, $salt), 0, 16);
  $hash eq $gen_hash
    or return $class->error($req, "Invalid hash supplied");

  return BSE::Template->get_refresh($url, $req->cfg);
}

1;
