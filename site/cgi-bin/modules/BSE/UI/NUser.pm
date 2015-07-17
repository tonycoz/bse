package BSE::UI::NUser;
use strict;
use base 'BSE::UI::Dispatch';

our $VERSION = "1.001";

sub controller_section {
  'nuser controllers';
}

sub dispatch {
  my ($class, $req) = @_;

  my $controller_id = $req->cgi->param('_p');
  my ($action, $rest);
  unless ($controller_id) {
    my @components = split '/', $ENV{PATH_INFO}, -1;
    shift @components if @components && $components[0] eq '';
    my @rest;
    ($controller_id, $action, @rest) = @components;
    $rest = join '/', @rest;
  }

  my $section = $class->controller_section;
  $controller_id ||= $req->cfg->entry($section, 'default');
  $controller_id
    or return $class->error($req, "No controller found in path");

  my $controller_class = 
    $req->cfg->entry($section, $controller_id)
      or return $class->error($req, "No class found for controller $controller_id");

  (my $controller_file = $controller_class . ".pm") =~ s!::!/!g;
  eval {
    local @INC = @INC;
    my $local_inc = $req->cfg->entry('paths', 'libraries');
    unshift @INC, $local_inc if $local_inc;

    require $controller_file;
  };
  if ($@) {
    my $error = $@;
    print STDERR "Error loading controller $controller_file: $error\n";
    eval {
      require BSE::TB::AuditLog;
      BSE::TB::AuditLog->log
	  (
	   component => "nadmin::load",
	   level => "critical",
	   actor => "S",
	   msg => "Failed to load module $controller_class",
	   dump => <<EOS
Class: $controller_class
File:  $controller_file
Error: $error
EOS
	  );
    };
    return $class->error($req, "Internal error: Could not load controller class");
  }
  my %opts;
  $action and $opts{action} = $action;
  defined $rest or $rest = '';
  $opts{rest} = $rest;
  $opts{controller_id} = $controller_id;
  my $controller = $controller_class->new(%opts);

  return $controller->dispatch($req);
}

1;

__END__

=head1 NAME

BSE::UI::NUser - dispatcher for user side functionality.

=cut
