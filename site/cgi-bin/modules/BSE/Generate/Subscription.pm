package BSE::Generate::Subscription;
use strict;
use vars qw(@ISA);
use BSE::Generate::Article;
@ISA = qw(BSE::Generate::Article);
use BSE::Util::HTML;

our $VERSION = "1.002";

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

sub tag_ifUser {
  my ($user, $args) = @_;

  $user or return '';
  $args or return 1;

  my $value = $user->{$args};
  defined $value or return '';

  return escape_html($value);
}

sub baseActs {
  my ($self, $articles, $acts, $article, $embedded) = @_;
  return 
    (
     $self->SUPER::baseActs($articles, $acts, $article, $embedded),
     ifUser => [ \&tag_ifUser, $self->{user} ],
     user =>
     sub {
       $self->{user} or return '';
       escape_html($self->{user}{$_[0]});
     },
     sub => sub { escape_html($self->{sub}{$_[0]}) },
    );
}

sub abs_urls {
  1;
}

sub abs_image_urls {
  1;
}

sub formatter_class {
  require BSE::Formatter::Subscription;
  return 'BSE::Formatter::Subscription'
}

sub image_url {
  my ($self, $im) = @_;

  $self->{cfg}->entryVar('site', 'url') . $self->SUPER::image_url($im);
}

1;

