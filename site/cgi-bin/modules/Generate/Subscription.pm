package Generate::Subscription;
use strict;
use vars qw(@ISA);
use Generate::Article;
@ISA = qw(Generate::Article);

sub set_user {
  my ($self, $user) = @_;

  $self->{user} = $user;
}

sub set_sub {
  my ($self, $sub) = @_;

  #use Data::Dumper;
  #print STDERR "set sub ",Dumper($sub);
  $self->{sub} = $sub;
}

sub baseActs {
  my ($self, $articles, $acts, $article, $embedded) = @_;
  return 
    (
     $self->SUPER::baseActs($articles, $acts, $article, $embedded),
     ifUser => sub { $self->{user} },
     user =>
     sub {
       $self->{user} or return '';
       CGI::escapeHTML($self->{user}{$_[0]});
     },
     sub => sub { CGI::escapeHTML($self->{sub}{$_[0]}) },
    );
}

1;

