package BSE::TB::Tags;
use strict;
use base 'Squirrel::Table';
use BSE::TB::Tag;

our $VERSION = "1.003";

sub rowClass {
  return 'BSE::TB::Tag';
}

sub split_name {
  my ($class, $name) = @_;

  my $cat = "";
  if ($name =~ s/^([^:]+): *//) {
    $cat = $1;
    $cat =~ s/^\s+//;
    $cat =~ s/\s+$//;
  }
  my $value = $name;
  $value =~ s/^\s+//;
  $value =~ s/\s+$//;

  return ($cat, $value);
}

my $bad_char = qr/[\\\/\x00-\x1F\x80-\x9F]/;

sub valid_name {
  my ($class, $name, $error) = @_;

  unless ($name =~ /\S/) {
    $$error = "empty";
    return;
  }

  my ($cat, $val) = $class->split_name($name);

  if ($cat =~ $bad_char || $val =~ /$bad_char/) {
    $$error = "badchars";
    return;
  }

  unless ($val =~ /\S/) {
    $$error = "emptyvalue";
    return;
  }

  return ($cat, $val);
}

=item valid_category

Test that the supplied category name is valid.

It must contain a trailing colon.

Returns the canonical form of the tag category.

=cut

sub valid_category {
  my ($class, $catname, $error) = @_;

  if ($catname =~ /$bad_char/) {
    $$error = "badchars";
    return;
  }

  $catname =~ s/^\s+//;
  $catname =~ s/\s+\z//;
  $catname =~ s/\s+:\z/:/;

  unless ($catname =~ /:\z/) {
    $$error = "nocolon";
    return;
  }

  return $catname;
}

sub make_name {
  my ($self, $cat, $val) = @_;

  return length $cat ? "$cat: $val" : $val;
}

sub name {
  my ($self, $name, $rerror) = @_;

  my ($cat, $val) = $self->valid_name($name, $rerror)
    or return;

  return $self->make_name($cat, $val);
}

sub canon_name {
  my ($self, $name, $error) = @_;

  my $res = $self->name($name, $error);
  defined $res
    or return;

  return lc $res;
}

sub getByName {
  my ($self, $owner_type, $name) = @_;

  my ($cat, $val) = $self->split_name($name);
  return $self->getBy(owner_type => $owner_type,
		      cat => $cat,
		      val => $val);
}

sub make_with_name {
  my ($self, $owner_type, $name) = @_;

  my ($cat, $val) = $self->split_name($name);
  return $self->make
    (
     owner_type => $owner_type,
     cat => $cat,
     val => $val,
    );
}

sub cleanup {
  return BSE::DB->single->run("bseTagsCleanup");
}

1;
