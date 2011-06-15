package BSE::Request::Test;
use strict;
use base 'BSE::Request::Base';

our $VERSION = "1.003";

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
  my ($self) = @_;

  $self->{session} = {};
}

sub is_ajax {
  $_[0]{is_ajax};
}

package BSE::Request::Test::CGI;
use Carp qw(confess);

sub param {
  my $self = shift;
  if (@_) {
    my $name = shift;
    if (@_) {
      die "Unabled to delete $name key in test";
    }
    else {
      my $value = $self->{$name};
      if (defined $value) {
	if (ref $value) {
	  if (wantarray) {
	    return @{$self->{$name}};
	  }
	  else {
	    return $self->{$name}[-1];
	  }
	}
	else {
	  return $value;
	}
      }
      else {
	return;
      }
    }
  }
  else {
    return keys %$self;
  }
}

1;
