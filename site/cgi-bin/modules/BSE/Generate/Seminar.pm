package BSE::Generate::Seminar;
use strict;
use base 'Generate::Product';
use BSE::TB::Seminars;
use DevHelp::HTML;
use BSE::Util::Tags qw(tag_hash);

sub baseActs {
  my ($self, $articles, $acts, $seminar, $embedded) = @_;

  unless ($seminar->isa('BSE::TB::Seminar')) {
    $seminar = BSE::TB::Seminars->getByPkey($seminar->{id});
  }
  return
    (
     $self->SUPER::baseActs($articles, $acts, $seminar, $embedded),
     seminar => [ \&tag_hash, $seminar ],
     admin => [ tag_admin => $self, $seminar, 'seminar', $embedded ],
    );
}

1;
