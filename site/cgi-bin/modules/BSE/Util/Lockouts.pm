package BSE::Util::Lockouts;
use strict;
use Carp qw(confess);
use BSE::TB::AuditLog;
use Scalar::Util qw(blessed);
use POSIX qw(strftime);

our $VERSION = "1.005";

sub check_lockouts {
  my ($class, %opts) = @_;

  exists $opts{user}
    or confess "Missing user parameter";
  my $user = $opts{user};
  my $section = $opts{section}
    or confess "Missing section parameter";
  my $component = $opts{component}
    or confess "Missing component parameter";
  my $module = $opts{module}
    or confess "Missing module parameter";
  my $req = $opts{request}
    or confess "Missing request parameter";
  my $type = $opts{type}
    or confess "Missing type parameter";

  my $cfg = BSE::Cfg->single;

  if ($user) {
    # user lockout check
    my $time_limit = $cfg->entry($section, "account_time_period", 10);
    my $fail_limit = $cfg->entry($section, "account_maximum_failures", 3);
    my @entries = BSE::TB::AuditLog->getSpecial
      (
       logonRecords => $user->id, blessed($user), $component, $module,
       $time_limit
      );
    my $bad_count = 0;
    for my $entry (@entries) {
      if ($entry->function eq 'success' || $entry->function eq 'unlock') {
	$bad_count = 0;
      }
      else {
	++$bad_count;
      }
    }

    if ($bad_count >= $fail_limit) {
      my $penalty = $cfg->entry($section, "account_lockout_time", 60);
      my $end = strftime("%Y-%m-%d %H:%M:%S", localtime(time() + $penalty * 60));
      $user->set_lockout_end($end);
      $user->save;

      $req->audit
	(
	 object => $user,
	 component => $component,
	 module => $module,
	 function => "lockout",
	 level => "error",
	 actor => "S",
	 msg => "Account '" . $user->logon . "' locked out until $end",
	 ip_address => $req->ip_address,
	);
    }
  }

  {
    # IP lockout check
    my $time_limit = $cfg->entry($section, "ip_time_period", 30);
    my $fail_limit = $cfg->entry($section, "ip_maximum_failures", 10);
    my $fail2_limit = $cfg->entry($section, "ip_maximum_failures2", 50);
    my @entries = BSE::TB::AuditLog->getSpecial
      (
       ipLogonRecords => $req->ip_address, $component, $module,
       $time_limit
      );
    my $bad_count = 0;
    my $bad2_count = 0;
    for my $entry (@entries) {
      if ($entry->function eq 'success') {
	$bad_count = 0;
      }
      elsif ($entry->function eq 'unlock') {
	$bad_count = 0;
	$bad2_count = 0;
      }
      else {
	++$bad_count;
	++$bad2_count;
      }
    }

    my $penalty;
    my $lock;
    if ($bad_count >= $fail_limit) {
      $penalty = $cfg->entry($section, "ip_lockout_time", 120);
      $lock = "";
    }
    elsif ($bad2_count >= $fail2_limit) {
      $penalty = $cfg->entry($section, "ip_lockout_time2", 120);
      $lock = "super-"
    }
    if ($penalty) {
      my $end = strftime("%Y-%m-%d %H:%M:%S", localtime(time() + $penalty * 60));
      my $db = BSE::DB->single;
      $db->run(bse_lockout_ip => $req->ip_address, $type, $end);
      $req->audit
	(
	 component => $component,
	 module => $module,
	 function => "lockout",
	 level => "error",
	 actor => "S",
	 msg => "IP address '" . $req->ip_address . "' ${lock}locked out until $end",
	 object => $user,
	 ip_address => $req->ip_address,
	);
    }
  }
}

sub unlock_user {
  my ($class, %opts) = @_;

  my $user = $opts{user}
    or confess "Missing user parameter";
  my $component = $opts{component}
    or confess "Missing component parameter";
  my $module = $opts{module}
    or confess "Missing module parameter";
  my $req = $opts{request}
    or confess "Missing request parameter";

  $req->audit
    (
     object => $user,
     component => $component,
     module => $module,
     function => "unlock",
     level => "notice",
     msg => "Account '" . $user->logon . "' unlocked",
     ip_address => $req->ip_address,
    );

  $user->set_lockout_end(undef);
  $user->save;
}

my %types =
  (
   "S" => "Site Users",
   "A" => "Admin Users",
  );

sub unlock_ip_address {
  my ($class, %opts) = @_;

  my $component = $opts{component}
    or confess "Missing component parameter";
  my $module = $opts{module}
    or confess "Missing module parameter";
  my $address = $opts{ip_address}
    or confess "Missing ip_address parameter";
  my $type = $opts{type}
    or confess "Missing type parameter";
  my $req = $opts{request}
    or confess "Missing request parameter";

  $types{$type}
    or confess "Unknown type $type\n";

  $req->audit
    (
     component => $component,
     module => $module,
     function => "unlock",
     level => "notice",
     msg => "IP Address '$address' unlocked for $types{$type} by ".$req->ip_address,
     ip_address => $address,
    );
}



1;
