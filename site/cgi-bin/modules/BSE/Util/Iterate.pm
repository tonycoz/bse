package BSE::Util::Iterate;
use strict;
use base 'DevHelp::Tags::Iterate';
use DevHelp::HTML;
use Carp 'confess';

sub escape {
  escape_html($_[1]);
}

sub _paged_save {
  my ($session, $name, @parms) = @_;

  $session->{"paged_$name"} = \@parms;
}

sub _paged_get {
  my ($session, $name) = @_;

  my $saved = $session->{"paged_$name"};
  return unless $saved;

  return @$saved;
}

# sub make_paged_iterator {
#   my ($self, $single, $plural, $rdata, $rindex, $cgi, $pagename,
#       $perpage_parm, $session, $name, $rstore) = @_;

#   return $self->SUPER::make_paged_iterator
#     ($single, $plural, $rdata, $rindex, $cgi, $pagename,
#      $perpage_parm, [ \&_paged_save, $session, $name ],
#      [ \&_paged_get, $session, $name ], $rstore);
# }

sub make_paged_iterator {
  my ($self, $single, $plural, $rdata, $rindex, $cgi, $pagename,
      $perpage_parm, $session, $name, $rstore) = @_;

  return $self->make_paged
    (
     single => $single,
     plural => $plural, 
     data => $rdata,
     index => $rindex,
     cgi => $cgi,
     pagename => $pagename,
     perpage_parm => $perpage_parm,
     store => $rstore,
     session => $session,
     name => $name,
    );
}

sub make_paged {
  my ($self, %opts) = @_;

  defined $opts{name} or confess "no name parameter supplied";
  defined $opts{session} or confess "No session parameter supplied";

  return $self->SUPER::make_paged
    (
     save => [ \&_paged_save, $opts{session}, $opts{name} ],
     get => [ \&_paged_get, $opts{session}, $opts{name} ],
     %opts
    );
}

package BSE::Util::Iterate::Article;
use vars qw(@ISA);
@ISA = 'BSE::Util::Iterate';
use Carp qw(confess);
use BSE::Util::Tags qw(tag_article);
use Constants qw($CGI_URI);
use BSE::Arrows;

sub new {
  my ($class, %opts) = @_;

  if ($opts{req}) {
    $opts{cfg} = $opts{req}->cfg;
  }

  $opts{cfg}
    or confess "cfg option mission\n";

  return $class->SUPER::new(%opts);
}

sub item {
  my ($self, $item, $args) = @_;

  return tag_article($item, $self->{cfg}, $args);
}

sub next_item {
  my ($self, $article, $name) = @_;

  if ($self->{req}) {
    $self->{req}->set_article($name => $article);
  }
}

sub more_tags {
  my ($self, $state) = @_;

  $state->{state}
    or return;

  return 
    (
     "move_$state->{single}" => [ move_article => $self, $state ],
    );
}

sub move_article {
  my ($self, $state, $args, $acts, $funcname, $templater) = @_;

  $self->{admin} or return '';
  my $parentid = $state->{parentid}
    or return '';
  @{$state->{data}} > 1 or return '';
  my $index = ${$state->{index}};
  my $rdata = $state->{data};
  defined $index && $index >= 0 && $index < @$rdata
    or return "** move_$state->{single} must be inside iterator $state->{plural} **";

  my ($img_prefix, $url_add) = 
    DevHelp::Tags->get_parms($args, $acts, $templater);
  $img_prefix = '' unless defined $img_prefix;
  $url_add = '' unless defined $url_add;
  my $refresh_to = $ENV{SCRIPT_NAME} . "?id=$self->{top}{id}$url_add";
  my $down_url = "";
  if ($index < $#$rdata) {
    $down_url = "$CGI_URI/admin/move.pl?stepparent=$parentid&d=swap&id=$rdata->[$index]{id}&other=$rdata->[$index+1]{id}";
  }
  my $up_url = "";
  if ($index > 0) {
    $up_url = "$CGI_URI/admin/move.pl?stepparent=$parentid&d=swap&id=$rdata->[$index]{id}&other=$rdata->[$index-1]{id}";
  }
  
  return make_arrows($self->{cfg}, $down_url, $up_url, $refresh_to, $img_prefix);
}

1;
