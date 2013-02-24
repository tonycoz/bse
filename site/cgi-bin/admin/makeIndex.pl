#!/usr/bin/perl -w
# -d:ptkdb
BEGIN { $ENV{DISPLAY} = '192.168.32.195:0.0' }
use strict;
use FindBin;
use lib "$FindBin::Bin/../modules";
use BSE::Request;
use BSE::Index;
use BSE::Util::HTML;
use Carp 'confess';

$SIG{__DIE__} = sub { confess $@ };

{
  my $req = BSE::Request->new;

  if (has_access($req)) {
    do_regen($req);
  }
}

sub has_access {
  my ($req) = @_;

  my $cfg = $req->cfg;
  my ($code, $msg, $url);
  if ($req->check_admin_logon()) {
    unless ($req->user_can("bse_makeindex")) {
      ($code, $msg) = ( "ACCESS", [ "msg:bse/admin/generic/accessdenied", [ "bse_makeindex" ] ] );
    }
  }
  else {
    ($code, $msg, $url) = ( "LOGON", [ "msg:bse/admin/logon/needlogon" ], $cfg->admin_url("logon") );
  }
  if ($code) {
    $url ||= $cfg->admin_url("menu");
    if ($req->want_json_response) {
      if (ref $msg) {
	$msg = $req->catmsg(@$msg);
      }
      $req->output_result
	($req->json_content
	 ({
	   success => 0,
	   error_code => $code,
	   message => $msg,
	   errors => {},
	  }));
    }
    else {
      $req->flash_error(@$msg);
      $req->output_result($req->get_refresh($url));
    }
    return;
  }

  return 1;
}

sub do_regen {
  my ($req) = @_;

  my $outputcb = sub {
    my $text = shift;
    defined $text or confess "undef output";
    if ($req->charset) {
      require Encode;
      Encode->import;
      $text = Encode::encode($req->charset, $text, Encode::FB_DEFAULT());
    }
    print $text;
  };

  my $cgi = $req->cgi;
  my $cfg = $req->cfg;
  my $verbose = $cgi->param("verbose") || 0;
  my $type = $cgi->param("type") || "html";
  my ($suffix, $permessage);
  my %acts;
  my ($errorcb, $notecb);
  if ($verbose) {
    ++$|;
    if ($type eq "html") {
      require BSE::Template;
      %acts = $req->admin_tags;
      $req->_set_vars();
      my $temp_result = BSE::Template->get_page("admin/makeindex", $req->cfg, \%acts, undef, undef, $req->{vars});
      (my ($prefix), $permessage, $suffix) =
	split /<:\s*iterator\s+(?:begin|end)\s+messages\s*:>/, $temp_result;
      print "Content-Type: ", BSE::Template->html_type($cfg), "\n\n";
      $outputcb->($prefix);
      my $out = sub {
	my ($error, @msg) = @_;
	$acts{ifError} = $error;
	$acts{message} = escape_html(join("", @msg));
	$outputcb->(BSE::Template->replace($permessage, $req->cfg, \%acts, $req->{vars}));
      };
      $errorcb = sub {
	my (@msg) = @_;
	
	$out->(1, @_);
      };
      $notecb = sub {
	$out->(0, @_);
      };
    }
    else {
      my $charset = $cfg->charset;
      print "Content-Type: text/plain; charset=$charset\n\n";
      $errorcb = $notecb = sub {
	my @msg = @_;
	$outputcb->(join("", @msg, "\n"));
      }
    }
  }
  
  my $good = eval {
    local $SIG{__DIE__};
    my $indexer = BSE::Index->new
      (
       error => $errorcb,
       note => $notecb,
      );
    $indexer->do_index();
    
    1;
  };
  if ($good) {
    if ($verbose) {
      my $msg = $req->catmsg("msg:bse/admin/makeindex/complete");
      $notecb->($msg);
      $outputcb->($suffix) if defined $suffix;
    }
    else {
      if ($req->want_json_response) {
	$req->output_result
	  ($req->json_content
	   ({
	     success => 1,
	    })
	  );
      }
      else {
	my $url = $cgi->param("r") || $cfg->admin_url("menu");
	$req->flash("msg:bse/admin/makeindex/complete");
	$req->output_result($req->get_refresh($url));
      }
    }
  }
  else {
    my $msg = $@;
    if ($verbose) {
      $errorcb->($msg);
    }
    else {
      if ($req->want_json_response) {
	$req->output_result
	  ($req->json_content
	   ({
	     success => 0,
	     error_code => "UNKNOWN",
	     message => $msg,
	     errors => {},
	    }));
      }
      else {
	my $url = $cfg->admin_url("menu");

	$req->flash_error($msg);
	$req->output_result($req->get_refresh($url));
      }
    }
  };
}


=head1 NAME

makeIndex.pl - regenerate the search index (CGI only)

=head1 SYNOPSIS

  http//example.com/cgi-bin/admin/makeIndex.pl
  http//example.com/cgi-bin/admin/makeIndex.pl?verbose=1
  http//example.com/cgi-bin/admin/makeIndex.pl?verbose=1&type=text

=head1 DESCRIPTION

Regenerates the BSE search index using the currently configured search
engine indexing module.

Parameters:

=over

=item *

C<verbose> - if a true perl value, display progress to the user, see
C<type> for the format of the progress.

If false, perform the indexing silently, flash a completion message
and refresh to the url indicated by the C<r> parameter, or the admin
menu by default.

=item *

C<type> - the type of output when C<verbose> is true.  The default,
"html", produces HTML output based on the template
C<admin/makeindex.tmpl>.

Otherwise produce C<text/plain> output in the current BSE character
set.

=item *

C<r> - the URL to refresh to after non-verbose search index regen.
Defaults to the main admin menu.

=back

=head1 SEE ALSO

bse_makeindex.pl, BSE::Index

=head1 AUTHOR

Tony Cook <tony@develop-help.com>

=cut

