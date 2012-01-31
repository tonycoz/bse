package BSE::TB::Site;
use strict;
use base qw(BSE::TB::SiteCommon);

our $VERSION = "1.001";

# like an article, but doesn't exist in the database

sub new {
  my ($class) = @_;

  return bless
    {
     id => -1,
     title => "Your site",
     generator => 'Generate::Article',
     parentid=>0,
     level => 0,
     body => '',
     flags => '',
     listed => 0,
    }, $class;
}

sub id {
  -1;
}

sub data_only {
  my ($self) = @_;

  return
    {
     map { $_ => $self->{$_} } grep /^[^_]/, keys %$self
    };
}

sub restricted_method {
  my ($self, $name) = @_;

  return $name =~ /^new$/;
}

1;
