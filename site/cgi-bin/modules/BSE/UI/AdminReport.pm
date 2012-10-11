package BSE::UI::AdminReport;
use strict;
use base 'BSE::UI::AdminDispatch';
use BSE::Util::Tags;
use BSE::Report;
use BSE::Util::HTML;

=head1 NAME

BSE::UI::AdminReport - reporting user interface

=head1 METHODS

=over

=cut

our $VERSION = "1.002";

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
     $req->admin_tags(),
     $reports->list_tags(),
     message => escape_html($msg),
     ifError => 1, # all messages we display are errors
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
     $req->admin_tags(),
     $reports->prompt_tags($repname, $req->cgi, BSE::DB->single),
     message => $msg,
     ifError => 1, # all messages we display are errors
    );

  my $template = $reports->prompt_template($repname) || 'admin/reports/prompt';

  return $req->dyn_response($template, \%acts);
}

=item target show

Display report results.

Parameters:

=over

=item *

r - report id

=item *

p1 ... pN - report parameters

=item *

sort - the sort method to use

=item *

type - the type of output, the default is C<html>, but may be set to
C<csv> for a CSV export of the report data.

=back

Extra parameters can be supplied for CSV output:

=over

=item *

filename - the filename to provide in the C<Content-Disposition>
header.  Defaults to C<< I<reportname>.csv >>.  Characters outside of
C<A-Za-z0-9_.-> are replaced with C<-> and duplicate C<-> are
squashed.

=item *

download - set to 0 to set C<Content-Disposition> to C<inline>.

=back

=cut

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

  my $type = $req->cgi->param('type') || 'html';
  if ($type eq 'csv') {
    return $class->_show_csv($req, $reports, $repname, \@params, sort => $sort);
  }

  my $msg;
  my %acts;
  %acts =
    (
     $req->admin_tags(),
     $reports->show_tags2($repname, BSE::DB->single, \$msg, \@params, %show_opts),
    );

  $msg
    and return $class->req_prompt($req, $msg);

  my $levels = $reports->levels($repname, BSE::DB->single);
  my $template = $reports->show_template($repname) || 'admin/reports/show' . $levels;

  return $req->dyn_response($template, \%acts);
}

sub _show_csv {
  my ($self, $req, $reports, $repname, $params, %opts) = @_;

  my $msg;
  my $result = $reports->report_data
    (
     $repname, BSE::DB->single, \$msg, $params,
     %opts
    )
      or return $self->_error($req, $msg);

  require Text::CSV;
  my $csv = Text::CSV->new({ binary => 1 });
  my $first = $result->[0];
  $csv->combine(@{$first->{titles}});
  my @out = $csv->string;
  for my $row (@{$first->{rows}}) {
    $csv->combine(@$row);
    push @out, $csv->string;
  }

  my $data = join("\n", @out, "");
  if ($req->cfg->utf8) {
    my $charset = $req->cfg->charset;
    require Encode;
    $data = Encode::encode($charset, $data);
  }

  my $filename = $req->cgi->param("filename");
  $filename ||= "$repname.csv";
  $filename =~ tr/a-zA-Z0-9_./-/cs;
  $filename =~ s/^-+//;
  my $download = $req->cgi->param("download");
  defined $download or $download = 1;
  my $disp = $download ? "attachment" : "inline";

  return
    {
     type => "text/plain",
     content => $data,
     headers =>
     [
      "Content-Disposition: $disp; filename=$filename"
     ],
    };
}

1;

=back

=cut
