package BSE::UI;
use strict;
use BSE::Cfg;

our $VERSION = "1.001";

sub confess;

sub run {
  my ($class, $ui_class, %opts) = @_;

  local $SIG{__DIE__} = sub { confess @_ };
  (my $file = $ui_class . ".pm") =~ s(::)(/)g;

  my $cfg = $opts{cfg} || BSE::Cfg->new;

  my $req;
  eval {
    require BSE::Request;
    $req = BSE::Request->new
      (
       cfg => $cfg,
       %{$opts{req_params} || {}},
      );
    1;
  } or fail("Loading request class: $@", "req", $cfg);

  eval {
    require $file;
    1;
  } or fail("Loading module $file: $@", "load", $cfg);

  eval {
    my $ui = $ui_class->new;
    my $result = $ui->dispatch($req);

    if (!$result && !$opts{silent_exit}) {
      confess "No content returned by dispatch()";
    }

    my $cfg = $req->cfg;
    undef $req; # release any locks
    if ($result) {
      require BSE::Template;
      BSE::Template->output_resultc($cfg, $result);
    }

    1;
  } or fail("Running dispatcher: $@", "run", $cfg);
}

sub run_fcgi {
  my ($class, $ui_class, %opts) = @_;

  local $SIG{__DIE__} = sub { confess @_ };
  (my $file = $ui_class . ".pm") =~ s(::)(/)g;

  my $cfg = $opts{cfg} || BSE::Cfg->new;

  eval {
    require $file;
    1;
  } or fail("Loading module $file: $@", "load", $cfg);

  require CGI::Fast;
  while (my $cgi = CGI::Fast->new) {
    my $req;
    eval {
      require BSE::Request;
      $req = BSE::Request->new
	(
	 cfg => $cfg,
	 cgi => $cgi,
	 fastcgi => $FCGI::global_request->IsFastCGI
	 %{$opts{req_params} || {}},
	);
      1;
    } or fail("Loading request class: $@", "req", $cfg);

    eval {
      my $ui = $ui_class->new;
      my $result = $ui->dispatch($req);

      if (!$result && !$opts{silent_exit}) {
	confess "No content returned by dispatch()";
      }

      my $cfg = $req->cfg;
      undef $req; # release any locks
      if ($result) {
	require BSE::Template;
	BSE::Template->output_resultc($cfg, $result);
      }

      1;
    } or fail("Running dispatcher: $@", "run", $cfg);
  }
}

sub confess {
  require Carp;

  goto &Carp::confess;
}

sub fail {
  my ($msg, $func, $cfg) = @_;

  print STDERR "run failure: $msg\n";
  eval {
    # try to log it
    require BSE::TB::AuditLog;
    my ($script) = $ENV{SCRIPT_NAME} =~ /(\w+)\.\w+$/;
    $script ||= "unknown";
    BSE::TB::AuditLog->log
	(
	 component => "$script:run",
	 function => $func,
	 level => "crit",
	 actor => "S",
	 msg => $msg,
	 dump => <<DUMP,
Error: $msg

\@INC: @INC
DUMP
	);
    1;
  } or print STDERR "Could not log: $@\n";

  print <<EOS;
Status: 500
Content-Type: text/plain

There was an error producing your content.
EOS
  exit 1;
}

1;
