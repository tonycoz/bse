package BSE::UI::AdminModules;
use strict;
use base "BSE::UI::AdminDispatch";
use BSE::Modules;
use BSE::Util::Iterate;
use BSE::Util::Prereq;

our $VERSION = "1.000";

my %actions =
  (
   modules => "bse_modules",
  );

sub rights { \%actions }

sub actions { \%actions }

sub req_modules {
  my ($self, $req) = @_;

  my $versions = \%BSE::Modules::versions;
  my $prereqs = \%BSE::Util::Prereq::prereqs;

  my $base = "$FindBin::Bin/../modules";

  my @modules;
  my @bad;
  for my $modname (sort keys %$versions) {
    my $module =
      {
       name => $modname,
       version => $versions->{$modname},
       found => "",
       error => "",
       notes => "",
      };
    (my $filename = $modname . ".pm") =~ s(::)(/)g;
    my $full = "$base/$filename";
    my $error = '';
    if (!$error && !-e $full) {
      $error = "Module file $filename not found";
    }
    my $content;
    if (!$error) {
      if (open my $in, "<", $full) {
	$content = do { local $/; <$in> };
	close $in;
      }
      else {
	$error = "Cannot open $full: $!";
      }
    }
    my $vers;
    if (!$error) {
      if ($content =~ /^our \$VERSION = "([0-9.]+)"/m) {
	$vers = $1;
	$module->{found} = $vers;
      }
      else {
	$error = "No version found in $filename";
      }
    }
    if (!$error) {
      if ($vers ne $versions->{$modname}) {
	$error = "Version $vers in file doesn't match expected $versions->{$modname}";
      }
    }

    if (!$error) {
      local $SIG{__DIE__};
      my $prereqs_good = 1;
      if ($prereqs->{$modname}) {
	for my $prereq (@{$prereqs->{$modname}}) {
	  if (!eval "require $prereq; 1") {
	    $module->{notes} = "Prerequisite $prereq not found";
	    $prereqs_good = 0;
	    last;
	  }
	}
      }
      if ($prereqs_good) {
	if (!eval "require $modname; 1") {
	  $error = "Cannot load $modname: $@";
	}
      }
    }
    $module->{error} = $error;
    if ($error) {
      push @bad, $module;
    }
    else {
      push @modules, $module;
    }
  }

  unshift @modules, @bad;

  my $it = BSE::Util::Iterate->new(req => $req);
  my %acts =
    (
     $req->admin_tags,
     $it->make
     (
      data => \@modules,
      single => "module",
      plural => "modules",
     ),
     hash => $BSE::Modules::hash,
    );

  return $req->response("admin/modules", \%acts);
}

1;
