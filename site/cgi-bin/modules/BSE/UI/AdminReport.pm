package BSE::UI::AdminReport;
use strict;
use base 'BSE::UI::AdminDispatch';
use BSE::Util::Tags;
use BSE::Report;
use DevHelp::HTML;

my %actions =
  (
   prompt => '',
   show => '',
   list_reports => '',
  );
  
sub actions {
  \%actions
}

sub action_prefix {
  's_'
}

sub rights {
  \%actions
}

sub default_action {
  'list_reports'
}

sub req_list_reports {
  my ($class, $req, $msg) = @_;

  my $reports = BSE::Report->new($req);
  
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
  
  return $req->dyn_response('admin/reports/list', \%acts);
}

sub req_prompt {
  my ($class, $req, $msg, $errors) = @_;
  
  my $reports = BSE::Report->new($req);
  
  my $repname = $req->cgi->param('r');
  
  defined $repname
    or return $class->req_list_reports($req, 'No report id supplied');
  
  $reports->valid_report($repname)
    or return $class->req_list_reports($req, 'Invalid report id supplied');

  $reports->report_accessible($repname)
    or return $class->req_list_reports($req, 'Report not accessible');
  
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

  return $req->dyn_response($template, \%acts);
}

sub req_show {
  my ($class, $req) = @_;

  my $reports = BSE::Report->new($req);
  
  my $repname = $req->cgi->param('r');
  
  defined $repname
    or return $class->req_list_reports($req, 'No report id supplied');
  
  $reports->valid_report($repname)
    or return $class->req_list_reports($req, 'Invalid report id supplied');
  
  $reports->report_accessible($repname)
    or return $class->req_list_reports($req, 'Report not accessible');
  
  my %errors;
  my @params = $reports->validate_params($repname, $req->cgi, 
					 BSE::DB->single, \%errors);
  keys %errors
    and return $class->req_prompt($req, '', \%errors);
  
  my %show_opts;
  my $sort = $req->cgi->param('sort');
  if (defined $sort && $sort =~ /^\d+$/) {
    $show_opts{sort} = $sort;
  }
  my $msg;
  my %acts;
  %acts =
    (
     BSE::Util::Tags->basic(\%acts, $req->cgi, $req->cfg),
     BSE::Util::Tags->admin(\%acts, $req->cfg),
     BSE::Util::Tags->secure($req),
     $reports->show_tags2($repname, BSE::DB->single, \$msg, \@params, %show_opts),
    );

  $msg
    and return $class->req_prompt($req, $msg);

  my $levels = $reports->levels($repname, BSE::DB->single);
  my $template = $reports->show_template($repname) || 'admin/reports/show' . $levels;

  return $req->dyn_response($template, \%acts);
}

1;
