package BSE::TB::AuditLog;
use strict;
use Squirrel::Table;
use vars qw(@ISA $VERSION);
@ISA = qw(Squirrel::Table);
use BSE::TB::AuditEntry;
use Scalar::Util qw(blessed);

our $VERSION = "1.008";

sub rowClass {
  return 'BSE::TB::AuditEntry';
}

# stop us recursing into here from BSE::ComposeMail
my $mailing = 0;

=head1 NAME

BSE::TB::AuditLog - audit log for BSE

=head1 METHODS

=over

=item log

Log a message to the audit log.

Required parameters:

=over

=item *

component - either a simple component name like "shop", or colon
separated component, module and function.

=item *

level - level of event, one of emerg, alert, crit, error, warning,
notice, info, debug.

=item *

actor - the entity performing the actor, one of a SiteUser object, an
AdminUser object, "S" for system, "U" for an unknown public user.

=item *

msg - a brief message

=item *

ip_address - the actor's IP address (optional, loaded from $REMOTE_ADDR).

=item *

object - an optional object being acted upon.

=item *

dump - an optional dump of debugging data

=back

=cut

sub log {
  my ($class, %opts) = @_;

  require BSE::Util::SQL;
  my %entry =
    (
     when_at => BSE::Util::SQL::now_datetime(),
    );

  my $facility = delete $opts{facility} || "bse";
  $entry{facility} = $facility;

  my $component = delete $opts{component}
    or $class->crash("Missing component");
  if ($component =~ /^(\w+):(\w*):(.+)$/) {
    @entry{qw/component module function/} = ( $1, $2, $3 );
  }
  elsif ($component =~ /^(\w+):(\w*)$/) {
    @entry{qw/component module/} = ( $1, $2 );
    $entry{function} = delete $opts{function} || delete $opts{action}
      or $class->crash("Missing function parameter");
  }
  else {
    $entry{component} = $component;
    $entry{module} = delete $opts{module} || '';
    $entry{function} = delete $opts{function} || delete $opts{action}
      or $class->crash("Missing function parameter")
  }

  my $object = delete $opts{object};
  if ($object) {
    $entry{object_type} = blessed $object;
    $entry{object_id} = $object->id;
  }
  else {
    $entry{object_type} = undef;
    $entry{object_id} = undef;
  }

  $entry{ip_address} = delete $opts{ip_address} || $ENV{REMOTE_ADDR} || '';
  my $level_name = delete $opts{level} || "emerg";
  $entry{level} = _level_name_to_id($level_name);

  my $actor = delete $opts{actor}
    or $class->crash("No actor supplied");

  if (ref $actor) {
    if ($actor->isa("BSE::TB::AdminUser")) {
      $entry{actor_type} = "A";
    }
    else {
      $entry{actor_type} = "M";
    }
    $entry{actor_id} = $actor->id;
  }
  else {
    if ($actor =~ /^[US]$/) {
      $entry{actor_type} = $actor;
    }
    else {
      $entry{actor_type} = "E";
    }
    $entry{actor_id} = undef;
  }

  $entry{msg} = delete $opts{msg}
    or $class->crash("No msg");
  my $dump = delete $opts{dump};
  my $bad_dump;
  if (defined $dump) {
    if (ref $dump) {
      if (blessed($dump)) {
	$bad_dump = "Dump data is blessed";
      }
      else {
	require JSON;

	my $json = JSON->new;
	$json->pretty;
	$json->canonical;
	eval {
	  $dump = $json->encode($dump);
	  1;
	} or $bad_dump = "Cannot encode dump reference to JSON: $@";
      }
    }
  }
  $entry{dump} = $dump;

  my $cfg = BSE::Cfg->single;

  my $section = "audit log $facility";
  unless ($cfg->entry
	  (
	   $section, join(":", @entry{qw/component module function/}),
	   $cfg->entry
	   (
	    $section, join(":", @entry{qw/component module/}),
	    $cfg->entry
	    (
	     $section, $entry{component}, 1
	    )
	   )
	  )
	 ) {
    return;
  }

  my $entry = $class->make(%entry);

  $entry->mail($cfg);

  keys %opts
    and $class->crash("Unknown parameters ", join(",", keys %opts), " to log()");

  $bad_dump
    and $class->crash($bad_dump);
}

sub crash {
  my ($class, @msg) = @_;

  @msg or push @msg, "Unknown";
  my $longmsg = Carp::longmess(@msg);
  $class->log
    (
     component => "unknown",
     module => "unknown",
     function => "unknown",
     level => "crit",
     actor => "S",
     msg => join("", @msg) || "Unknown",
     dump => $longmsg,
    );
  die $longmsg;
}

my @level_names = qw(emerg alert crit error warning notice info debug);
my %level_name_to_id;
@level_name_to_id{@level_names} = 0 .. $#level_names;
my %level_id_to_name;
@level_id_to_name{0 .. $#level_names} = @level_names;

sub _level_name_to_id {
  my ($name) = @_;

  # default to 0 (emerg)
  return $level_name_to_id{$name} || 0;
}

sub level_id_to_name {
  my ($class, $id) = @_;

  return $level_id_to_name{$id} || sprintf("unknown-%d", $id);
}

=item object_log

Return log entries for the supplied object.

=cut

sub object_log {
  my ($self, $object, $rules, $options) = @_;

  my %options;
  %options = %$options if $options;
  $options{order} ||= "when_at desc";

  my @rules =
    (
     [ object_type => blessed $object ],
     [ object_id => $object->id ],
    );
  push @rules, $rules if $rules;

  return $self->getBy2(\@rules, \%options);
}

1;

=back

=head1 AUTHOR

Tony Cook <tony@develop-help.com>

=cut
