package BSE::Request::Test;
use strict;
use base 'BSE::Request::Base';

sub new {
  my ($class, %opts) = @_;

  my $self = $class->SUPER::new(%opts);
  $self->{session} = {};

  $self;
}

sub _make_cgi {
  bless {}, 'BSE::Request::Test::CGI';
}

package BSE::Request::Base::Test;

sub param {
  return; # nothing for now
}

1;
