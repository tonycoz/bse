package BSE::UI::Redirect;
use strict;
use base qw(BSE::UI::Dispatch);
use Digest::MD5 qw(md5_hex);
use DevHelp::HTML;

my %actions =
  (
   redir => 1
  );

sub actions { \%actions };

sub default_action { 'redir' }

sub req_redir {
  my ($self, $req) = @_;

  my $cgi = $req->cgi;
  my $url = $cgi->param('url')
    or return $self->error($req, "No url supplied");
  my $text = $cgi->param('t') || $url;
  my $hash = $cgi->param('h')
    or return $self->error($req, "No hash supplied");
  my $salt = $req->cfg->entry('html', 'redirect_salt', '');
  my $gen_hash = substr(md5_hex($url, $text, $salt), 0, 16);

  $hash eq $gen_hash
    or return $self->error($req, "Invalid hash supplied");

  my %acts =
    (
     $req->dyn_user_tags(),
     url => escape_html($url),
     text => escape_html($text),
    );

  return $req->dyn_response('user/redirect', \%acts);
}

1;
