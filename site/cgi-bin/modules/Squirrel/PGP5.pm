package Squirrel::PGP5;
use strict;

sub new {
  return bless {}, $_[0];
}

sub error {
  return $_[0]->{error};
}

sub encrypt {
  my ($self, $recips, $data, %opts) = @_;

  my @recips = ref $recips ? @$recips : ( $recips );
  my $cmd = $opts{pgp} || 'pgp';
  $cmd .= ' ';
  ++$opts{sign} if $opts{secretkeyid};
  my $flags = "afe";
  if ($opts{sign} && !$opts{passphrase}) {
    $self->{error} = "Cannot sign without passphrase"; 
    return 
  }
  
  $flags .= "s" if $opts{sign};
  $cmd .= "-$flags ";
  $cmd .= "-u $opts{secretkeyid} " if $opts{secretkeyid};
  
  # do the deed
  my $child = open CHILD, "-|";
  defined $child or do { $self->{error} = "Cannot fork: $!"; return };
  unless ($child) {
    $ENV{PGPPASSFD} = 0 if $opts{sign};
    print STDERR "PGP command: $cmd\n" if $opts{debug};
    if (open PGP, "| $cmd") {
      select(PGP); $| = 1; select(STDOUT);
      print $opts{passphrase}, "\n" if $opts{sign};
      print $data;
      close PGP
	or do { print "*ERROR* $?/$!\n"; exit 1; };
    }
    else {
      print "*ERROR* $!\n";
      exit 1;
    }

    exit 0; # finish the child
  }

  # ... and back in the parent process
  my @data = <CHILD>;
  print STDERR "Data out: @data\n" if $opts{debug};
  my $result = close CHILD;
  if (!$result) {
    print STDERR __PACKAGE__," Error\n" if $opts{debug};
    # something went wrong, try to figure out what
    if ($? >> 8) {
      print STDERR __PACKAGE__," non-zero from child\n" if $opts{debug};
      # first child returned non-zero
      my @errors = grep /^\*ERROR*/, @data;
      if (@errors) {
       
	$self->{error} = substr($errors[0], 7);
      }
      else {
	$self->{error} = "Unknown error";
      }
    }
    else {
      $self->{error} = "Unknown error: $!";
    }
    print STDERR __PACKAGE__," $self->{error}\n" if $opts{debug};
    return undef;
  }

  return join('', @data);
}

1;

=head1 NAME

  Squirrel::PGP5

=head1 SYNOPSIS

  use Squirrel::PGP5;
  my $pgp = Squirrel::PGP5->new;
  my $data = ...;
  my @recips = ( 'foo@bar.com' );
  my $pass = ...; # passphase, required for sign
  my $keyid = '9876BCED';
  my $crypted = $pgp->encrypt(\@recips, $data, passphrase=>$pass,
			      sign=>1, keyid=>$keyid)
    or die "Cannot encrypt: ",$pgp->error;

=head1 BUGS

Doesn't attempt to overwrite copies of keys and so on.  This probably
isn't worth the trouble in Perl, since copies of all that would have
been in mortals passed into functions.

Needs more documentation.

=cut
