package BSE::Request::Test;
use strict;
use base 'BSE::Request::Base';

our $VERSION = "1.004";

sub new {
  my ($class, %opts) = @_;

  my $params = delete $opts{params} || {};
  my %params = %$params;
  my $files = delete $opts{files} || {};
  for my $key (%$files) {
    $params{$key} = $files->{$key}{name};
  }
  $opts{cgi} = bless
    {
     params => \%params,
     files => $files,
    }, 'BSE::Request::Test::CGI';
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
use File::Temp qw(:seekable);

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

sub upload {
  my ($self, $name) = @_;

  my $entry = $self->{files}{$name}
    or return;

  $entry->{handle}
    and return $entry->{handle};

  my $fh;
  if ($entry->{content}) {
    my $temp = BSE::Request::CGI::File->new;
    binmode $temp;
    print $temp $entry->{content};
    $temp->seek(0, SEEK_SET);

    $fh = $temp;
  }
  else {
    open $fh, "<", $entry->{filename}
      or die "Cannot open file $entry->{filename}: $!";
    binmode $fh;
  }
  $entry->{handle} = $fh;

  return $fh;
}

sub uploadInfo {
  my ($self, $name) = @_;

  my $entry = $self->{files}{$name}
    or return;

  return $entry->{info} || {};
}

package BSE::Request::CGI::File;
use base 'File::Temp';

sub handle {
  $_[0];
}

1;
