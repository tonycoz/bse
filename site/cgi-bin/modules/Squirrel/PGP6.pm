package Squirrel::PGP6;
use strict;

our $VERSION = "1.000";

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
  #++$opts{sign} if $opts{secretkeyid};
  my $flags = "feat";
  if ($opts{sign} && !$opts{passphrase}) {
    $self->{error} = "Cannot sign without passphrase"; 
    return 
  }
  
  $flags .= "s" if $opts{sign};
  $cmd .= "-$flags ";
  $cmd .= "-u$opts{secretkeyid} " if $opts{secretkeyid};
  $cmd .= "'$_' " for @recips;
  
  # do the deed
  my $child = open CHILD, "-|";
  defined $child or do { $self->{error} = "Cannot fork: $!"; return };
  unless ($child) {
    $ENV{PGPPASSFD} = 0 if $opts{sign};
    $ENV{VERBOSE} = $opts{verbose} if exists $opts{verbose};
    if ($opts{home}) {
      $ENV{HOME} = $opts{home};
    }
    else {
      my @uinfo = getpwuid $<;
      if (@uinfo) {
        $ENV{HOME} = $uinfo[7];
        print STDERR "HOME set to $ENV{HOME}\n" if $opts{debug};
      }
      else {
        print STDERR "Could not get user info for $<\n" if $opts{debug};
      }
    }
    print STDERR "PGP command: $cmd\n" if $opts{debug};
    if (open PGP, "| $cmd") {
      select(PGP); $| = 1; select(STDOUT);
      print PGP $opts{passphrase}, "\n" if $opts{sign};
      print PGP $data;
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

  Squirrel::PGP6

=head1 SYNOPSIS

  use Squirrel::PGP6;
  my $pgp = Squirrel::PGP6->new;
  my $data = ...;
  my @recips = ( 'foo@bar.com' );
  my $pass = ...; # passphase, required for sign
  my $keyid = '9876BCED';
  my $crypted = $pgp->encrypt(\@recips, $data, passphrase=>$pass,
			      sign=>1, keyid=>$keyid)
    or die "Cannot encrypt: ",$pgp->error;

=head1 METHODS

=over 4

=item $pgp->encrypt(\@recips, $data, %opts)

Encrypts $data using the public keys of @recips.  %opts can contain
the following keys:

pgp - path to the pgp executable (defaults to just 'pgp')

sign - the message is signed with the user's private key if this is
true.  The passphrase must also be set.

passphrase - the passphrase used to access the private key

secretkeyid - the secret key used to sign the message

debug - some debugging information is sent to STDERR if this is set

verbose - the environment variable VERBOSE is set to this if set.

home - used to set the HOME environment variable.  If this isn't set
then the $dir result from getpwuid $< will be used.

=item $pgp->error()

Returns the last error seen.

=back

=head1 BUGS

Doesn't attempt to overwrite copies of keys and so on.  This probably
isn't worth the trouble in Perl, since copies of all that would have
been in mortals passed into functions.

Doesn't handle error returns from pgp, not that pgp6 returns much in
the way of useful error information.

Needs more documentation.

=head1 SEE ALSO

Squirrel::GPG(3), gpg(1)

=cut
