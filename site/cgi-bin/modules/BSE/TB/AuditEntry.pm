package BSE::TB::AuditEntry;
use strict;
use base qw(Squirrel::Row);

our $VERSION = "1.009";

=head1 NAME

BSE::TB::AuditEntry - an entry in the audit log.

=head1 METHODS

=over

=cut

sub columns {
  return qw/id 
            when_at
	    facility
	    component
	    module
	    function
	    level
	    actor_type
	    actor_id
	    object_type
	    object_id
	    ip_address
	    msg
	    dump
	   /;
}

sub table {
  "bse_audit_log";
}

=item when_at

=item facility

=item component

=item module

=item function

=item level

=item actor_type

=item actor_id

=item object_type

=item object_id

=item ip_address

=item msg

=item dump

Simple accessors.

=item level_name

Retrieve the level as text.

=cut

sub level_name {
  my ($self) = @_;

  return BSE::TB::AuditLog->level_id_to_name($self->level);
}

=item actor_name

Retrieve description of the actor.

=cut

sub actor_name {
  my ($self) = @_;

  my $type = $self->actor_type;
  if ($type eq "U") {
    return "Unknown";
  }
  elsif ($type eq "E") {
    return "Error";
  }
  elsif ($type eq "S") {
    return "System";
  }
  elsif ($type eq "A") {
    require BSE::TB::AdminUsers;
    my $admin = BSE::TB::AdminUsers->getByPkey($self->actor_id);
    if ($admin) {
      return "Admin: ".$admin->logon;
    }
    else {
      return "Admin: " . $self->actor_id. " (not found)";
    }
  }
  elsif ($type eq "M") {
    require SiteUsers;
    my $user = SiteUsers->getByPkey($self->actor_id);
    if ($user) {
      return "Member: ".$user->userId;
    }
    else {
      return "Member: ".$self->actor_id . " (not found)";
    }
  }
  else {
    return "Unknown type $type";
  }
}

=item actor_link

Retrieve a link to the actor.

=cut

sub actor_link {
  my ($self) = @_;

  my $type = $self->actor_type;
  if ($type eq "A") {
    require BSE::TB::AdminUsers;
    my $admin = BSE::TB::AdminUsers->getByPkey($self->actor_id);
    if ($admin) {
      return $admin->link;
    }
    else {
      return "";
    }
  }
  elsif ($type eq "M") {
    require SiteUsers;
    my $user = SiteUsers->getByPkey($self->actor_id);
    if ($user) {
      return $user->link;
    }
    else {
      return "";
    }
  }
  else {
    return "";
  }
}

my %types =
  (
   "BSE::TB::Order" =>
   {
    target => "shopadmin",
    action => "order_detail",
    format => "Order %d",
   },
   "SiteUser" =>
   {
    target => "siteusers",
    action => "view",
    format => "Member %d",
    class => "SiteUsers",
   },
   "BSE::TB::AdminUser" =>
   {
    target => "adminusers",
    action => "showuser",
    format => "Admin: %d",
    class => "BSE::TB::AdminUsers",
    idname => "userid",
   },
  );

=item object_link

Retrieve a link to the object.

=cut

sub object_link {
  my ($self) = @_;

  my $id = $self->object_id or return "";
  my $type = $self->object_type;
  my $entry = $types{$type};
    my $cfg = BSE::Cfg->single;
  if ($entry) {
    my $idname = $entry->{idname} || "id";
    return $cfg->admin_url2($entry->{target}, $entry->{action},
			    { $idname => $id });
  }
  else {
    my $link_action = $cfg->entry("type $type", "link_action");
    my $link_target = $cfg->entry("type $type", "link_target");
    if ($link_action && $link_target) {
      return $cfg->admin_url2($link_target, $link_action,
			      { id => $id });
    }
    else {
      return "";
    }
  }
}

=item object_name

Retrieve a name for the object.

=cut

sub object_name {
  my ($self) = @_;

  my $type = $self->object_type
    or return '(None)';
  my $entry = $types{$type};
  my $cfg = BSE::Cfg->single;
  my $method = $cfg->entry("type $type", "method", "describe");
  my $format = $cfg->entry("type $type", "format",
			  ($entry && $entry->{format}) ? $entry->{format} : "");
  my $obj = $self->object;
  if ($obj && $obj->can($method)) {
    return $obj->$method();
  }
  elsif ($format) {
    return sprintf $format, $self->object_id;
  }
  else {
    return $type . ": " . $self->object_id;
  }
}

=item object

Attempts retrieve the object for the log entry.

=cut

sub object {
  my ($self) = @_;

  my $type = $self->object_type
    or return;

  my $entry = $types{$type};
  my $cfg = BSE::Cfg->single;
  my $class = $cfg->entry("type $type", "class", $entry->{class});
  my $obj;
  if ($class
      && eval "use $class; 1"
      && ($obj = $class->getByPkey($self->object_id))) {
    return $obj;
  }

  return;
}

=item mail()

=cut

=item mail

Used internally to mail audit log entries.

Template tags are common static tags and:

=over

=item *

C<< entry I<field> >> - object tag for the log entry.

=back

Template variable:

=over

=item *

C<entry> - the log entry object.

=item *

C<to> - the recipients

=back

=cut

my $mailing;

sub mail {
  my ($entry, $cfg) = @_;

  $mailing
    and return;

  $cfg ||= BSE::Cfg->single;
  my $section = "mail audit log";
  my $to = $cfg->entry($section, "to", $cfg->entry("shop", "from"));
  my ($facility, $component, $module, $function) =
    map $entry->$_(), qw(facility component module function);
  my @look =
    (
     [ $section, "$facility-$component" ],
     [ $section, "$facility-$component-$module" ],
     [ $section, "$facility-$component-$module-$function" ],
    );
  my $send = $cfg->entry($section, $entry->level_name, 0);
  $send =~ /\@/ and $to = $send;
  for my $choice (@look) {
    $send = $cfg->entry(@$choice, $send);
    $send =~ /\@/ and $to = $send;
  }
  if ($send) {
    $mailing = 1;
    eval {
      require BSE::ComposeMail;
      if ($to) {
	require BSE::Util::Tags;
	my $mailer = BSE::ComposeMail->new(cfg => $cfg);
	my %acts =
	  (
	   BSE::Util::Tags->static(undef, $cfg),
	   entry => [ \&BSE::Util::Tags::tag_object, $entry ],
	  );
	$mailer->send(to => $to,
		      subject => "BSE System Event",
		      template => "admin/log/mail",
		      acts => \%acts,
		      vars =>
		      {
		       to => $to,
		       entry => $entry,
		      });
      }
    };
    $mailing = 0;
  }
}

sub restricted_method {
  my ($self, $name) = @_;

  return $self->SUPER::restricted_method($name)
    || $name =~ /^(?:mail)$/;
}

1;

=back

=head1 AUTHOR

Tony Cook <tony@develop-help.com>

=cut

