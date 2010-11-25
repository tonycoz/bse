package BSE::CGI;
use strict;
use Encode;

our $VERSION = "1.000";

sub new {
  my ($class, $q, $charset) = @_;

  my $self = bless
    {
     cgi => $q,
     charset => $charset,
    }, $class;

  return $self;
}

sub param {
  my ($self, @args) = @_;

  my @result = $self->{cgi}->param(@args)
    or return;
  for my $value (@result) {
    $value = decode($self->{charset}, $value);
  }

  return wantarray && @result > 1 ? @result : $result[0];
}

sub upload {
  my ($self, @args) = @_;

  return $self->{cgi}->upload(@args);
}

sub uploadInfo {
  my ($self, @args) = @_;

  return $self->{cgi}->uploadInfo(@args);
}

1;

=head1 NAME

BSE::CGI - CGI.pm wrapper that does character set conversions to perl's internal encoding

=head1 SYNOPSIS

  my $cgi1 = CGI->new;
  my $cgi = BSE::CGI->new($cgi1, $charset);

=head1 DESCRIPTION

Only provides param(), upload() and uploadInfo().

=cut