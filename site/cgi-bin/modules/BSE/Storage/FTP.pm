package BSE::Storage::FTP;
use strict;
use BSE::Storage::Base;
our @ISA = qw(BSE::Storage::Base);
use Net::FTP;
use Carp qw(confess);

our $VERSION = "1.000";

sub new {
  my ($class, %opts) = @_;

  my $self = $class->SUPER::new(%opts);

  my $cfg = $self->cfg;
  for my $key (qw/baseurl host cwd user password/) {
    $self->{$key} = $self->configure($key);
    defined $self->{$key}
      or confess "Missing $key from configuration";
  }
  $self->{passive} = $self->configure('passive', 0);
  $self->{chmod} = $self->configure('chmod');

  return $self;
}

sub _connect {
  my ($self) = @_;

  my $ftp = Net::FTP->new($self->{host}, Passive => $self->{passive});
  $ftp
    or die "Cannot connect via ftp to $self->{host}: $@\n";

  $ftp->login($self->{user}, $self->{password})
    or die "Cannot login to $self->{host}: ", $ftp->message, "\n";

  $ftp->cwd($self->{cwd})
    or die "Cannot cwd to $self->{cwd} on $self->{host}: ", $ftp->message, "\n";

  $ftp->binary
    or die "Cannot switch to binary mode on $self->{host}: ", $ftp->message, "\n";

  return $ftp;
}

sub store {
  my ($self, $local_name, $basename, $http_extras) = @_;

  my $ftp = $self->_connect;
  unless ($ftp->put($local_name, $basename)) {
    my $put_error = $ftp->message;
    # remove it, in case of a partial transfer
    $ftp->delete($basename);
    $ftp->quit;

    die "Cannot store $local_name to $basename on $self->{host}: $put_error\n";
  }

  if ($self->{chmod}) {
    unless ($ftp->site("chmod $self->{chmod} $basename")) {
      my $chmod_error = $ftp->message;
      # remove it, in case of a partial transfer
      $ftp->delete($basename);
      $ftp->quit;
      
      die "Cannot chmod $local_name on $self->{host}: $chmod_error\n";
    }
  }

  $ftp->quit;

  return $self->{baseurl} . $basename;
}

sub unstore {
  my ($self, $basename) = @_;

  my $ftp = $self->_connect;
  my $success = $ftp->delete($basename);
  $ftp->quit;

  return $success;
}

sub list {
  my ($self) = @_;

  my $ftp = $self->_connect;
  my @files = $ftp->ls;
  $ftp->quit;

  return grep !/^\.\.?$/, @files;
}

sub url {
  my ($self, $basename) = @_;

  $self->{baseurl} . $basename;
}

1;

=head1 NAME

BSE::Storage::FTP - storage that stores via FTP.

=head1 SYNOPSIS

  [ftpimages]
  class=BSE::Storage::FTP
  baseurl=http://yourisp.com/images/
  cwd=/public_html/images/
  user=ftpuser
  password=ftppassword
  cond=...

=head1 DESCRIPTION

This is a BSE storage that accesses the remote store via FTP.

=cut
