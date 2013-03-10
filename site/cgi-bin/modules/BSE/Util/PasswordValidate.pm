package BSE::Util::PasswordValidate;
use strict;
use Carp qw(confess);
use Scalar::Util qw(reftype);

our $VERSION = "1.000";

=head1 NAME

BSE::PasswordValidate - validate password strength as configured

=head1 SYNOPSIS

  use BSE::PasswordValidate;
  unless (BSE::PasswordValidate->validate
    (
    password => $password,
    username => $username,
    rules => $rules,
    other => $other)) {
    # fail
  }

=head1 DESCRIPTION

Validate a user supplied password.

=over

=item validate(password => $password, username => $name, other => $other, rules => $rules, errors =>\@errors)

C<$password> is the password to validate.

C<$rules> is a hashref of rules to check.  Possible keys are:

C<$name> is the user name to match against (C<notuser> and C<notu5er>
validation.)

C<$other> is other fields to match the password agains (currently
unused).

=over

=item *

C<length> - the minimum length for passwords

=item *

C<entropy> - the minimum entropy as measured by Data::Password::Entropy

=item *

C<symbols> - non-alphanumerics/spaces are required

=item *

C<digits> - digits are required.

=item *

C<mixedcase> - both upper and lower case are required.

=item *

C<categories> - number of character categories out of 5 required out
of symbols, digits, upper case, lower case and extended ASCII/Unicode
characters.

=item *

C<notuser> - the password may not match the user name case-insensitively.

=item *

C<notu5ser> - the password may not match the user name
case-insensitively, even with symbol replacement (e.g. "5" for "S".

=back

=cut

sub validate {
  my ($class, %opts) = @_;

  my $self = bless \%opts, $class;

  $opts{password} =~ s/\A\s+//;
  $opts{password} =~ s/\s+\z//;

  defined $opts{password}
    or confess "Missing password parameter";
  exists $opts{username}
    or confess "Missing username paramater";
  ref $opts{rules} && reftype $opts{rules} eq "HASH"
    or confess "Missing or invalid rules parameter";
  ref $opts{errors} && reftype $opts{errors} eq "ARRAY"
    or confess "Missing or invalid errors parameter";
  ref $opts{other} && reftype $opts{other} eq "HASH"
    or confess "Missing or invalid other parameter";
  
  my $good = 1;
  for my $rule (keys %{$opts{rules}}) {
    my $method = "_validate_$rule";
    unless ($self->can($method)) {
      confess "Unknown rule $rule\n";
    }
    if ($opts{rules}{$rule} && !$self->$method($opts{rules}{$rule})) {
      $good = 0;
    }
  }

  unless ($good) {
    @{$self->{errors}} = sort
      {
	( ref $a ? $a->[0] : $a )
	  cmp
	    ( ref $b ? $b->[0] : $b )
      } @{$self->{errors}};
  }

  return $good;
}

sub _validate_length {
  my ($self, $length) = @_;

  if (length($self->{password}) < $length) {
    push @{$self->{errors}}, join ":", "msg:bse/util/password/length",
			       length $self->{password}, $length;
    return;
  }

  return 1;
}

sub _validate_entropy {
  my ($self, $entropy) = @_;

  require Data::Password::Entropy;
  Data::Password::Entropy->import();
  my $found_entropy = password_entropy($self->{password});
  if ($found_entropy < $entropy) {
    push @{$self->{errors}}, join ":", "msg:bse/util/password/entropy",
			       $found_entropy, $entropy, $found_entropy/$entropy * 100;
    return;
  }

  return 1;
}

sub _validate_symbols {
  my ($self) = @_;

  unless ($self->{password} =~ /\W/) {
    push @{$self->{errors}}, "msg:bse/util/password/symbols";
    return;
  }

  return 1;
}

sub _validate_digits {
  my ($self) = @_;

  unless ($self->{password} =~ /\d/) {
    push @{$self->{errors}}, "msg:bse/util/password/digits";
    return;
  }

  return 1;
}

sub _validate_mixedcase {
  my ($self) = @_;

  unless ($self->{password} =~ /\p{Ll}/
	  && $self->{password} =~ /\p{Lu}/) {
    push @{$self->{errors}}, "msg:bse/util/password/mixedcase";
    return;
  }

  return 1;
}

sub _validate_categories {
  my ($self, $count) = @_;

  my $found_count = 0;
  for ($self->{password}) {
    $found_count++ if /\p{Ll}/;
    $found_count++ if /\p{Lu}/;
    $found_count++ if /\pN/;
    $found_count++ if /[^\pL\pN]/;
    $found_count++ if /[^\x00-\x9F]/;
  }

  if ($found_count < $count) {
    push @{$self->{errors}},
      join ":", "msg:bse/util/password/categories", $found_count, $count;
    return;
  }

  return 1;
}

sub _validate_notuser {
  my ($self) = @_;

  if ($self->{username} =~ /\Q$self->{password}/i
     || $self->{password} =~ /\Q$self->{username}/i) {
    push @{$self->{errors}}, "msg:bse/util/password/notuser";
    return;
  }

  return 1;
}

my @u5er_sets = 
  (
   [ qw(a 4 @) ],
   [ qw(b 8) ],
   [ qw(e 3) ],
   [ qw(g 6) ],
   [ qw(i l 1) ],
   [ qw(o 0) ],
   [ qw(q 9) ],
   [ qw(s 5 $) ],
   [ qw(t 7) ],
   [ qw(z 2) ],
  );

my %u5er_map;
{
  for my $set (@u5er_sets) {
    for my $entry (@$set) {
      $u5er_map{$entry} = "[" . join("", @$set) . "]";
    }
  }
}

sub _validate_notu5er {
  my ($self) = @_;

  (my $work_pw = $self->{password}) =~
    s/(.)/$u5er_map{lc $1} || quotemeta $1/ige;
  (my $work_user = quotemeta $self->{username}) =~
    s/(.)/$u5er_map{lc $1} || quotemeta $1/ige;

  if ($self->{username} =~ qr/$work_pw/i
      || $self->{password} =~ qr/$work_user/i) {
    push @{$self->{errors}}, "msg:bse/util/password/notu5er";
    return;
  }

  return 1;
}

=back

=cut

1;
