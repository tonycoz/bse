package BSE::Generate::Seminar;
use strict;
use base 'Generate::Product';
use BSE::TB::Seminars;
use DevHelp::HTML;
use BSE::Util::Tags qw(tag_hash);
use BSE::Util::Iterate;

sub baseActs {
  my ($self, $articles, $acts, $seminar, $embedded) = @_;

  unless ($seminar->isa('BSE::TB::Seminar')) {
    $seminar = BSE::TB::Seminars->getByPkey($seminar->{id});
  }
  my $it = BSE::Util::Iterate->new;
  my $location;
  return
    (
     $self->SUPER::baseActs($articles, $acts, $seminar, $embedded),
     seminar => [ \&tag_hash, $seminar ],
     admin => [ tag_admin => $self, $seminar, 'seminar', $embedded ],
     $it->make_iterator([ \&iter_sessions, $seminar ], 'session', 'sessions'),
     $it->make_iterator
     ([ \&iter_locations, $seminar ], 'location', 'locations',
      undef, undef, undef, \$location),
     $it->make_iterator
     ([ \&iter_location_sessions, $seminar, \$location ], 'location_session',
      'location_sessions', undef, undef, 'nocache'),
    );
}

sub iter_sessions {
  my ($seminar) = @_;

  $seminar->future_session_info;
}

sub iter_locations {
  my ($seminar) = @_;

  $seminar->future_locations;
}

sub iter_location_sessions {
  my ($seminar, $rlocation) = @_;

  $$rlocation or return;

  $seminar->future_location_sessions($$rlocation);
}

1;
