package BSE::Request::Test;
use strict;
use base 'BSE::Request::Base';

our $VERSION = "1.001";

sub new {
  my ($class, %opts) = @_;

  my $params = delete $opts{params} || {};
  $opts{cgi} = bless $params, 'BSE::Request::Test::CGI';
  $opts{is_ajax} ||= 0;
  my $self = $class->SUPER::new(%opts);

  $self;
}

sub _make_cgi {
  bless {}, 'BSE::Request::Test::CGI';
}

sub _make_session {
  return {};
}

sub is_ajax {
  $_[0]{is_ajax};
}

package BSE::Request::Base::Test;

sub param {
  my $self = shift;
  if (@_) {
    my $name = shift;
    if (@_) {
    }
    else {
      if (ref $self->{$name}) {
	if (wantarray) {
	  return @{$self->{$name}};
	}
	else {
	  return $self->{$name}[-1];
	}
      }
      else {
	return $self->{$name};
      }
    }
  }
  else {
    return keys %$self;
  }
}

1;
