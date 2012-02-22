package Squirrel::Template::Deparser;
use strict;
use Squirrel::Template::Constants qw(:node);

our $VERSION = "1.000";

sub deparse {
  my ($class, $item) = @_;

  my $method = "deparse_$item->[NODE_TYPE]";

  return $class->$method($item);
}

sub deparse_comp {
  my ($class, $item) = @_;

  return join("", map $class->deparse($_), @{$item}[NODE_COMP_FIRST .. $#$item]);
}

sub deparse_cond {
  my ($class, $item) = @_;

  return $item->[NODE_ORIG]
    . $class->deparse($item->[NODE_COND_TRUE])
      . "<:or:>"
	. $class->deparse($item->[NODE_COND_FALSE])
	  . "<:eif:>";
}

sub deparse_iterator {
  my ($class, $item) = @_;

  return $item->[NODE_ORIG] . $class->deparse($item->[NODE_ITERATOR_LOOP])
    . "<:iterator separator $item->[NODE_TAG_NAME]:>"
      . $class->deparse($item->[NODE_ITERATOR_SEPARATOR])
    . "<:iterator end $item->[NODE_TAG_NAME]:>";
}

sub deparse_with {
  my ($class, $item) = @_;

  return $item->[NODE_ORIG] . $class->deparse($item->[NODE_WITH_CONTENT])
    . "<:with end $item->[NODE_TAG_NAME]:>";
}

sub deparse_wrap {
  my ($class, $item) = @_;

  return $item->[NODE_ORIG] . $class->deparse($item->[NODE_WRAP_CONTENT])
    . "<:endwrap:>";
}

sub deparse_switch {
  my ($class, $item) = @_;

  return $item->[NODE_ORIG]
    . join("", map {;
      $_->[0][NODE_ORIG] . $class->deparse($_->[1])
    } @{$item->[NODE_SWITCH_CASES]})
      . "<:endswitch:>";
}

sub deparse_content {
  my ($class, $item) = @_;

  return $item->[NODE_ORIG];
}

sub deparse_tag {
  my ($class, $item) = @_;

  return $item->[NODE_ORIG];
}

sub deparse_wraphere {
  my ($class, $item) = @_;

  return $item->[NODE_ORIG];
}

sub deparse_error {
  my ($class, $item) = @_;

  return "";
}

sub deparse_empty {
  my ($class, $item) = @_;

  return "";
}

1;
