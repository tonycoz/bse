#!/usr/bin/perl -w
# -d:ptkdb
BEGIN { $ENV{DISPLAY} = '192.168.32.51:0.0' }
use strict;
use FindBin;
use lib "$FindBin::Bin/../modules";
use Articles;
use CGI qw(:standard);
use Constants;
use BSE::Regen qw(generate_button generate_all generate_article generate_base generate_one_extra pregenerate_list);
use BSE::WebUtil qw(refresh_to_admin);
use Carp 'verbose';
use BSE::Request;
use BSE::Util::HTML;
use BSE::CfgInfo 'admin_base_url';

my $req = BSE::Request->new;

my $cfg = $req->cfg;
my $cgi = $req->cgi;
my $siteurl = admin_base_url($cfg);
unless ($req->check_admin_logon()) {
  if ($req->want_json_response) {
    $req->output_result($req->logon_error);
  }
  else {
    $req->output_result($cfg->admin_url("logon"));
  }
  exit;
}

my $articles = "Articles";

my $id = $cgi->param('id');
my $fromid = $cgi->param('fromid') || $id;
my $baseurl;
if (defined $fromid
    and my $fromart = Articles->getByPkey($fromid)) {
  $baseurl = $fromart->{admin};
}
else {
  $baseurl = $cfg->admin_url("menu");
}

if ($cgi->param("r")) {
  ($baseurl) = $cgi->param("r");
}

my $type_name;
my $progress = $cgi->param('progress');
my $good = eval {
  if (generate_button()) {
    my $callback;
    if ($progress) {
      $| = 1;
      my $charset = $cfg->charset;
      print <<HTML;
Content-Type: text/html; charset=$charset

<?xml version="1.0" encoding="$charset"?>
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN"
   "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd" >
<html>
  <head>
    <title>Regenerating your site</title>
    <link rel="stylesheet" href="/css/admin.css" type="text/css" />
  </head>
  <body id="regen">
  <h1>Regenerating</h1>
HTML
      $callback = sub { print "<div>",escape_html($_[0]),"</div>" };
    }
    if (defined $id) {
      my $article;
      if ($id eq 'extras' || $id =~ /^extra:./) {
	$req->user_can('regen_extras')
	  or die { error_code => "ACCESS", message => "Access denied - you need regen_extras access" };
      }
      else {
	$article = Articles->getByPkey($id)
	  or die { error_code => "NOTFOUND", message => "No such article $id found" };
	$req->user_can('regen_article', $article)
	  or die { error_code => "ACCESS", message => "Access denied - you don't have regen_article access on article $id" };
      }
      if ($article) {
	generate_article($articles, $article, $cfg);
	$type_name = "of article $id (" . $article->title . ")";
      }
      elsif ($id eq "extras") {
	my $last_set = "";
	generate_base(cfg => $cfg,
		      progress =>
		      sub {
			my ($data, $note) = @_;
			$callback or return;
			if (!$data->{count} &&
			    $data->{set} ne $last_set) {
			  print "<h2>Regenerating $data->{set} pages</h2>\n";
			  $last_set = $data->{set};
			}
			$callback->($note);
		      });
	$type_name = "of extras";
      }
      elsif ($id =~ /^extra:(.*)$/) {
	my $name = $1;
	my @extras = pregenerate_list($cfg);
	my ($extra) = grep $_->{name} eq $name, @extras
	  or die { error_code => "EXTRANOTFOUND", message => "No extra named $name found" };

	print "<p>Generating ", escape_html($extra->{name}), "</p>\n"
	  if $progress;
	generate_one_extra($articles, $extra);
	$type_name = "of extra $extra->{name}";
      }
      else {
	die { error_code => "UNKNOWN", message => "Unknown regenerate spec $id" };
      }
    }
    else {
      $req->user_can('regen_all')
	or die { error_code => "ACCESS", message => "You don't have regen_all access" };
      generate_all($articles, $cfg, $callback);
      $type_name = "of your site";
    }
  }
  else {
    die { error => "DISABLED", message => "Manual generation is disabled" };
  }

  1;
};

my $error;
unless ($good) {
  $error = $@;

  if (ref $error) {
    if ($progress) {
      print qq(<p class="error">) . escape_html($error->{message}) . "</p>\n";
    }
    elsif ($req->want_json_response) {
      $error->{success} = 0;
      $req->output_result($req->json_content($error));
      exit;
    }
    else {
      $req->flash_error($error->{message});
      $baseurl = $cfg->admin_url("menu");
    }
  }
  else {
    # page build error of some sort
    if ($progress) {
      # just do it inline
      print qq(<p class="error">Error during regeneration: ) . escape_html($error) . "</p>\n";
    }
    elsif ($req->want_json_response) {
      my $result =
	{
	 success => 0,
	 error_code => "BUILD",
	 message => "Error during regenereration: " . $error,
	 errors => {},
	};
      $req->output_result($req->json_content($result));
      exit;
    }
    else {
      $req->flash_error("Error during regeneration: " . escape_html($error));
      $baseurl = $cfg->admin_url("menu");
    }
  }
}

if ($progress) {
  print qq!<p>Done <a href="/cgi-bin/admin/menu.pl">Return to admin menu</a></p>\n!;
  print "</body></html>\n";
}
else {
  if (!$error && $baseurl eq $cfg->admin_url("menu") || $cgi->param("m")) {
    $req->flash("Regeneration $type_name complete");
  }
  $req->output_result($req->get_refresh($baseurl));
}

__END__

=head1 NAME

generate.pl - regenerate a BSE site, or parts of it.

=head1 SYNOPSIS

  http://example.com/cgi-bin/admin/generate.pl

=head1 DESCRIPTION

Regenerates a BSE site or the specified parts.

Parameters:

=over

=item *

C<id> - an article id, C<extras>, or C<< extra:I<template-name> >>.
If not supplied the entire site is regenerated.

=item *

C<fromid> - an article id to redirect to after the regen is complete.

=item *

C<progress> - if supplied and true, display progress information.  If
progress is displayed no redirect is performed.

=item *

C<r> - the URL to redirect to on successful completion.  Overrides
C<fromid>.  Default: the admin menu.  If an error occurs during a
non-C<progress> regen the user will be returned to the admin menu
where an error will be displayed.

=item *

C<m> - normally, on a successful regeneration, a success message is
flashed only if the redirect URL is the admin menu.  If C<m> is
supplied and true this forces the success message to be flashed for
any redirect URL.

=back

=head1 AUTHOR

Tony Cook <tony@develop-help.com>

=cut
