#!/usr/bin/perl -w
# -d:ptkdb
BEGIN { $ENV{DISPLAY} = '192.168.32.15:0.0' }
use strict;
use FindBin;
use lib "$FindBin::Bin/../modules";
use BSE::DB;
use BSE::Request;
use BSE::Template;
use BSE::Permissions;
use BSE::Util::Tags;
use DevHelp::Report;
use DevHelp::HTML;
use BSE::WebUtil 'refresh_to';

my $req = BSE::Request->new;
my $cgi = $req->cgi;

BSE::Permissions->check_logon($req)
  or do { refresh_to($req->url('logon'), $req->cfg); exit };

my $reports = DevHelp::Report->new($req->cfg, 'reports');

if ($cgi->param('s_prompt') || $cgi->param('s_prompt.x')) {
  prompt($req, $reports);
}
elsif ($cgi->param('s_show') || $cgi->param('s_show.x')) {
  show($req, $reports);
}
else {
  list_reports($req, $reports);
}

sub list_reports {
  my ($req, $reports, $msg) = @_;

  $msg = '' unless defined $msg;
  my %acts;
  %acts =
    (
     BSE::Util::Tags->basic(\%acts, $req->cgi, $req->cfg),
     BSE::Util::Tags->admin(\%acts, $req->cfg),
     BSE::Util::Tags->secure($req),
     $reports->list_tags(),
     message => escape_html($msg),
    );
  
  return BSE::Template->show_page('admin/reports/list', $req->cfg, \%acts);
}

sub prompt {
  my ($req, $reports, $msg, $errors) = @_;
  
  my $repname = $req->cgi->param('r');
  
  defined $repname
    or return list_reports($req, $reports, 'No report id supplied');
  
  $reports->valid_report($repname)
    or return list_reports($req, $reports, 'Invalid report id supplied');
  
  defined $msg or $msg = '';
  if (keys %$errors && $msg eq '') {
    $msg = join "<br>", map "<b>".escape_html($_)."</b>", values %$errors;
  }
  else {
    $msg = escape_html($msg);
  }
  
  my %acts;
  %acts =
    (
     BSE::Util::Tags->basic(\%acts, $req->cgi, $req->cfg),
     BSE::Util::Tags->admin(\%acts, $req->cfg),
     BSE::Util::Tags->secure($req),
     $reports->prompt_tags($repname, $req->cgi, BSE::DB->single),
     message => $msg,
    );

  my $template = $reports->prompt_template($repname) || 'admin/reports/prompt';

  return BSE::Template->show_page($template, $req->cfg, \%acts);
}

sub show {
  my ($req, $reports) = @_;

  my $repname = $req->cgi->param('r');
  
  defined $repname
    or return list_reports($req, $reports, 'No report id supplied');
  
  $reports->valid_report($repname)
    or return list_reports($req, $reports, 'Invalid report id supplied');
  
  my %errors;
  my @params = $reports->validate_params($repname, $req->cgi, 
					 BSE::DB->single, \%errors);
  keys %errors
    and return prompt($req, $reports, '', \%errors);
  
  my $msg;
  my %acts;
  %acts =
    (
     BSE::Util::Tags->basic(\%acts, $req->cgi, $req->cfg),
     BSE::Util::Tags->admin(\%acts, $req->cfg),
     BSE::Util::Tags->secure($req),
     $reports->show_tags($repname, BSE::DB->single, \$msg, @params),
    );

  $msg
    and return prompt($req, $reports, $msg);

  my $levels = $reports->levels($repname, BSE::DB->single);
  my $template = $reports->show_template($repname) || 'admin/reports/show' . $levels;

  return BSE::Template->show_page($template, $req->cfg, \%acts);
}
