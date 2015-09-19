package BSE::UI;
use strict;
use BSE::Cfg;

our $VERSION = "1.005";

my $time = sub { time };

if (eval { require Time::HiRes; 1 }) {
  $time = \&Time::HiRes::time;
}

sub confess;

sub run {
  my ($class, $ui_class, %opts) = @_;

  local $SIG{__DIE__} = sub { confess @_ };
  (my $file = $ui_class . ".pm") =~ s(::)(/)g;

  my $cfg = $opts{cfg} || BSE::Cfg->new;

  my $start = $time->();

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
      $cfg->entry("basic", "times", 0)
	and _show_times($start, $result);
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
    if ($cfg->utf8) {
      require BSE::CGI;
      $cgi = BSE::CGI->new($cgi, $cfg->charset);
    }
    my $start = $time->();
    my $req;
    eval {
      require BSE::Request;
      $req = BSE::Request->new
	(
	 cfg => $cfg,
	 cgi => $cgi,
	 fastcgi => scalar $CGI::Fast::Ext_Request->IsFastCGI,
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
	$cfg->entry("basic", "times", 0)
	  and _show_times($start, $result);

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

sub _show_times {
  my ($start, $result) = @_;

  if ($result->{type}
      && $result->{type} =~ m(^text/html)
      && $result->{content}) {
    my %mem = qw(VmPeak unknown VmSize unknown);

    $mem{time} = sprintf("%.1f", 1000 * ($time->() - $start));
    if (open my $meminfo, "<", "/proc/$$/status") {
      while (my $line = <$meminfo>) {
	chomp $line;
	$line =~ /(\w+):\s+(.*)/ and $mem{$1} = $2;
      }
      close $meminfo;
    }
    $result->{content} =~ s/<!--pagegen:(\w+)-->/$mem{$1} || "unknown"/ge;
    if ($result->{headers}) {
      my $length = length $result->{content};
      for my $header (@{$result->{headers}}) {
	$header =~ s/(Content-Length: ).*/$1$length/
	  and last;
      }
    }
  }
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
