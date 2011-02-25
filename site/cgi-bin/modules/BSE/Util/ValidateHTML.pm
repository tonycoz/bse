package BSE::Util::ValidateHTML;
use strict;

our $VERSION = "1.000";

sub validate {
  my ($class, $cfg, $result) = @_;

  for my $validator (split /,/, $cfg->entry("html", "validator", "Tidy")) {
    my $real_class = "BSE::Util::ValidateHTML::$validator";

    my $valid;
    unless (eval {
      (my $file = $real_class . ".pm") =~ s(::)(/)g;
      require $file;
      $valid = $real_class->validate($cfg, $result);
      1;
    }) {
      require BSE::TB::AuditLog;
      BSE::TB::AuditLog->log
	  (
	   component => "template:validatehtml:load",
	   level => "critical",
	   actor => "S",
	   msg => "Could not load $real_class",
	   dump => $@,
	  );
      return;
    }
    $valid or return;
  }

  return 1;
}

1;
