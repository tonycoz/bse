package BSE::Util::ValidateHTML::W3C;
use strict;
use WebService::Validator::HTML::W3C;

our $VERSION = "1.000";

sub validate {
  my ($self, $cfg, $result) = @_;

  my $v = WebService::Validator::HTML::W3C->new(detailed => 1);

  unless ($v->validate_markup($result->{content})) {
    require BSE::TB::AuditLog;
    BSE::TB::AuditLog->log
	(
	 component => "template:validatehtml:request",
	 level => "crit",
	 actor => "S",
	 msg => "Cannot validate HTML: " . $v->validator_error,
	);
    return;
  }

  unless ($v->is_valid) {
    # synthesize a filename
    my $fname = $ENV{SCRIPT_NAME};
    $fname .= $ENV{PATH_INFO} if $ENV{PATH_INFO};
    $fname .= "?" . $ENV{QUERY_STRING} if $ENV{QUERY_STRING};

    my @messages = map
      {
	"line " . $_->line . " col " . $_->col . ": " . $_->msg
      } @{$v->errors};

    my $resp = eval { $v->_content } || '';
    require BSE::TB::AuditLog;
    BSE::TB::AuditLog->log
	(
	 component => "template:validatehtml_w3c:validate",
	 level => "error",
	 actor => "S",
	 msg => "Page $fname failed HTML validation",
	 dump => join("\n", @messages) . "\n\n$resp",
	);

    return;
  }

  return 1;
}

1;
