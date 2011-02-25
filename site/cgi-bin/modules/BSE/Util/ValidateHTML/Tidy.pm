package BSE::Util::ValidateHTML::Tidy;
use strict;
use HTML::Tidy;

our $VERSION = "1.000";

my %ignore =
  (
   error => TIDY_ERROR,
   warning => TIDY_WARNING,
   info => TIDY_INFO,
  );

sub validate {
  my ($class, $cfg, $result) = @_;

  my %tidy_opts = $cfg->entriesCS("html tidy");

  my $ignore_types = delete $tidy_opts{ignore_types};
  my @ignore_text = delete @tidy_opts{grep /^ignore_text_/, keys %tidy_opts};

  my $tidy = HTML::Tidy->new(\%tidy_opts);

  if ($ignore_types) {
    for my $key (split /,/, $ignore_types) {
      if ($ignore{$key}) {
	$tidy->ignore(type => $ignore{$key});
      }
    }
  }

  for my $ignore_text (@ignore_text) {
    $tidy->ignore(text => qr/$ignore_text/);
  }

  # synthesize a filename
  my $fname = $ENV{SCRIPT_NAME};
  $fname .= $ENV{PATH_INFO} if $ENV{PATH_INFO};
  $fname .= "?" . $ENV{QUERY_STRING} if $ENV{QUERY_STRING};

  $tidy->parse($fname, $result->{content});

  my @messages = $tidy->messages;
  if (@messages) {
    require BSE::TB::AuditLog;
    BSE::TB::AuditLog->log
	(
	 component => "template:validatehtml_tidy:validate",
	 level => "error",
	 actor => "S",
	 msg => "Page $fname failed HTML validation",
	 dump => join("\n", @messages),
	);

    return;
  }

  return 1;
}

1;
