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

sub make_paged_iterator {
  my ($self, $single, $plural, $rdata, $rindex, $cgi, $pagename,
      $perpage_parm, $session, $name, $rstore) = @_;

  defined $name or confess "no \$name parameter supplied";
  
  return $self->SUPER::make_paged_iterator
    ($single, $plural, $rdata, $rindex, $cgi, $pagename,
     $perpage_parm, [ \&_paged_save, $session, $name ],
     [ \&_paged_get, $session, $name ], $rstore);
}

package BSE::Util::Iterate::Article;
use vars qw(@ISA);
@ISA = 'BSE::Util::Iterate';
use Carp qw(confess);
use BSE::Util::Tags qw(tag_article);

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

1;
