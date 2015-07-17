package BSE::UI::AdminModules;
use strict;
use base "BSE::UI::AdminDispatch";
use BSE::Modules;
use BSE::Util::Iterate;
use BSE::Util::Prereq;

our $VERSION = "1.002";

my %actions =
  (
   modules => "bse_modules",
  );

sub rights { \%actions }

sub actions { \%actions }

=item modules

Displays the result of the module check.

Tags:

=over

=item *

hash - the module version hash, if this has changed, then a module
version has changed.

=item *

iterator modules (single: module) - iterates over the modules checked.
Modules with errors are listed first, but modules are otherwise listed
alphabetically.

=back

Each module has the following fields:

=over

=item *

name - the module name

=item *

version - the version from BSE::Modules

=item *

found - the module version number found installed

=item *

error - an errors that occurred

=item *

notes - any reason the module was not checked.  Only one of C<error>
and C<notes> can be set.

=back

Template: admin/modules

Permissions: bse_modules

=cut

sub req_modules {
  my ($self, $req) = @_;

  my $versions = \%BSE::Modules::versions;
  my $prereqs = \%BSE::Util::Prereq::prereqs;

  my $base = "$FindBin::Bin/../modules";

  my @modules;
  my @bad;
  my %prereqs_checked;
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
    unless ($error) {
      if (open my $in, "<", $full) {
	$content = do { local $/; <$in> };
	close $in;
      }
      else {
	$error = "Cannot open $full: $!";
      }
    }
    my $vers;
    unless ($error) {
      if ($content =~ /^our \$VERSION = "([0-9.]+)"/m) {
	$vers = $1;
	$module->{found} = $vers;
      }
      else {
	$error = "No version found in $filename";
      }
    }
    unless ($error) {
      if ($vers ne $versions->{$modname}) {
	$error = "Version $vers in file doesn't match expected $versions->{$modname}";
      }
    }

    unless ($error) {
      local $SIG{__DIE__};
      my $prereqs_good = 1;
      if ($prereqs->{$modname}) {
	for my $prereq (@{$prereqs->{$modname}}) {
	  my $good_prereq;
	  if (exists $prereqs_checked{$prereq}) {
	    $good_prereq = $prereqs_checked{$prereq};
	  }
	  else {
	    $good_prereq = eval "require $prereq; 1";
	    $prereqs_checked{$prereq} = $good_prereq;
	  }
	  unless ($good_prereq) {
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
  $req->set_variable(modules => \@modules);
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
