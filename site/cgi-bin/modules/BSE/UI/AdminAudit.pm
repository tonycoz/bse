package BSE::UI::AdminAudit;
use strict;
use base "BSE::UI::AdminDispatch";
use BSE::TB::AuditLog;
use BSE::Util::Iterate;
use BSE::Util::Tags qw(tag_object);

our $VERSION = "1.000";

my %actions =
  (
   log => "bse_log_list",
   detail => "bse_log_detail",
  );

sub default_action { "log" }

sub actions { \%actions }

sub rights { \%actions }

# sub _strip_arg {
#   my ($rargs, $col, $val) = @_;

#   return [ grep $_->{col} ne $col || $_->{val} ne $val, @$rargs ];
# }

# sub tag_addarg {
#   my ($self, $rargs, $args, $acts, $func_name, $templater) = @_;

#   my (@args) = DevHelp::Tags->get_parms($args, $acts, $templater);
#   my @orig_args = @args;
#   my $work = $rargs;
#   while (@args > 1) {
#     $work = _strip_arg($work, splice(@args, 0, 2));
#   }

#   return BSE::Cfg->single->admin_url
#     (log => { (map { $_->{col} => $_->{val} } @$work), @orig_args });
# }

# sub tag_delarg {
#   my ($self, $rargs, $args, $acts, $func_name, $templater) = @_;

#   my (@args) = DevHelp::Tags->get_parms($args, $acts, $templater);
#   my $work = $rargs;
#   while (@args > 1) {
#     $work = _strip_arg($work, splice(@args, 0, 2));
#   }

#   return BSE::Cfg->single->admin_url
#     (log => { map { $_->{col} => $_->{val} } @$work });
# }

sub req_log {
  my ($self, $req, $errors) = @_;

  my @query;
  my @args;
#   my @cols = BSE::TB::AuditEntry->columns;
#   shift @cols;
#   my $cgi = $req->cgi;
#   for my $col (@cols) {
#     my @values = $cgi->param($col);
#     if (@values) {
#       push @query,
# 	[
# 	 "or",
# 	 map [ "=", $col, $_ ], @values
# 	];
#       push @args, map +{ col => $col, val => $_ }, @values;
#     }
#   }

  my @ids = 
    BSE::TB::AuditLog->getColumnBy( "id", \@query, { order => "id desc" });

  $req->cache_set(auditlog => \@ids);

  my $message = $req->message($errors);

  my $it = BSE::Util::Iterate::Objects->new(req => $req);
  my $h_it = BSE::Util::Iterate->new(req => $req);
  my %recs;
  my %acts =
    (
     $req->admin_tags,
     $it->make_paged
     (
      single => "auditentry",
      plural => "auditlog",
      fetch => [ getByPkey => "BSE::TB::AuditLog" ],
      name => "auditlog",
      session => $req->session,
      data => \@ids,
      perpage_parm => "pp=50",
      cgi => $req->cgi,
     ),
#      addarg => [ tag_addarg => $self, \@args ],
#      delarg => [ tag_delarg => $self, \@args ],
#      $h_it->make
#      (
#       data => \@args,
#       single => "arg",
#       plural => "args",
#      ),
     message => $message,
    );

  return $req->response("admin/log/log", \%acts);
}

sub req_detail {
  my ($self, $req) = @_;

  my %errors;
  my $id = $req->cgi->param("id");
  unless ($id && $id =~ /^[0-9]+$/) {
    $errors{id} = "Missing or invalid log entry id";
  }
  my $entry;
  unless (%errors) {
    $entry = BSE::TB::AuditLog->getByPkey($id)
      or $errors{id} = "No such log entry";
  }
  keys %errors
    and return $self->req_log($req, \%errors);
  my $nextid = '';
  my $previd = '';
  my $ids = $req->cache_get("auditlog");
  if ($ids) {
    my ($id_index) = grep $id == $ids->[$_], 0..$#$ids;
    if (defined $id_index) {
      $id_index > 0 and $previd = $ids->[$id_index-1];
      $id_index < $#$ids and $nextid = $ids->[$id_index+1];
    }
  }

  my %acts =
    (
     $req->admin_tags,
     auditentry => [ \&tag_object, $entry ],
     next_auditentry_id => $nextid,
     prev_auditentry_id => $previd,
    );

  return $req->response("admin/log/entry", \%acts);
}

1;
