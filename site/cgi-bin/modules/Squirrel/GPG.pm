package Squirrel::GPG;

sub new {
  return bless {}, $_[0];
}

sub error {
  return $_[0]->{error};
}

sub encrypt {
  my ($self, $recips, $data, %opts) = @_;

  my @recips = ref $recips ? @$recips : ( $recips );
  my $cmd = $opts{gpg} || 'gpg';
  $cmd .= ' ';
  ++$opts{sign} if $opts{secretkeyid};
  my $flags = "aqe";
  if ($opts{sign} && !$opts{passphrase}) {
    $self->{error} = "Cannot sign without passphrase"; 
    return;
  }
  
  $flags .= "s" if $opts{sign};
  $cmd .= "-$flags ";
  $cmd .= "-u $opts{secretkeyid} " if $opts{secretkeyid};
  $cmd .= $opts{opts} if $opts{opts};
  for (@recips) {
    $cmd .= "-r '$_' ";
  }
  $cmd .= "--no-tty ";
  # do the deed
  my $child = open CHILD, "-|";
  defined $child or do { $self->{error} = "Cannot fork: $!"; return };
  unless ($child) {
    $cmd .= "--passphrase-fd 0 " if $opts{sign};
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
    print STDERR "GPG command: $cmd\n" if $opts{debug};
    if (open PGP, "| $cmd 2>&1") {
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
  my $result = close CHILD;
  print STDERR "GPG Output", @data if $opts{debug};
  if ($opts{stripwarn} && $data[0] =~ /^\w+: Warning:/) {
    shift @data;
  }
  if (!$result) {
    # something went wrong, try to figure out what
    if ($? >> 8) {
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
    return undef;
  }

  return join('', @data);
}

1;

__END__

=head1 NAME

  Squirrel::GPG

=head1 SYNOPSIS

  use Squirrel::GPG;
  my $gpg = Squirrel::GPG->new;
  my $data = ...;
  my @recips = ( 'foo@bar.com' );
  my $pass = ...; # passphase, required for sign
  my $keyid = '9876BCED';
  my $crypted = $gpg->encrypt(\@recips, $data, passphrase=>$pass,
			      sign=>1, keyid=>$keyid)
    or die "Cannot encrypt: ",$gpg->error;

=head1 METHODS

=over 4

=item $gpg->encrypt(\@recips, $data, %opts)

Encrypts $data using the public keys of @recips.  %opts can contain
the following keys:

gpg - path to the gpg executable (defaults to just 'gpg')

sign - the message is signed with the user's private key if this is
true.  The passphrase must also be set.

passphrase - the passphrase used to access the private key

secretkeyid - the secret key used to sign the message

debug - if set then some debugging information will be written to STDERR

opts - extra command-line options

stripwarn - strips the insecure memory warning from the output if
present (see BUGS in gpg(1))

home - used to set the HOME environment variable.  If this isn't set
then the $dir result from getpwuid $< will be used.

=item $gpg->error()

Returns the last error seen.

=back

=head1 BUGS

Doesn't attempt to overwrite copies of keys and so on.  This probably
isn't worth the trouble in Perl, since copies of all that would have
been in mortals passed into functions.

Doesn't handle error returns from gpg (ie. output to STDERR).

Needs more documentation.

=head1 SEE ALSO

Squirrel::PGP6(3), gpg(1)

=cut
