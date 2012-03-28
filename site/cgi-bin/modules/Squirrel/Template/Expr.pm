package Squirrel::Template::Expr;
use strict;

our $VERSION = "1.000";

package Squirrel::Template::Expr::Parser;

sub new {
  my ($class) = @_;

  return bless {}, $class;
}

sub parse {
  my ($self, $text) = @_;

  my $tokenizer = Squirrel::Template::Expr::Tokenizer->new($text);
  return $self->_parse_expr($tokenizer);
}

sub _parse_expr {
  my ($self, $tok) = @_;

  return $self->_parse_or($tok);
}

my %ops =
  (
   "op+" => "+",
   "op-" => "-",
   "op*" => "*",
   "op/" => "/",
   "div" => "div",
   "mod" => "mod",
   "op_" => "concat",
  );

sub _parse_or {
  my ($self, $tok) = @_;

  my $result = $self->_parse_and($tok);
  while ($tok->peektype eq 'or') {
    my $op = $tok->get;
    my $other = $self->_parse_and($tok);
    $result = [ or => $result, $other ];
  }

  return $result;
}

sub _parse_and {
  my ($self, $tok) = @_;

  my $result = $self->_parse_rel($tok);
  while ($tok->peektype eq 'and') {
    my $op = $tok->get;
    my $other = $self->_parse_rel($tok);
    $result = [ and => $result, $other ];
  }

  return $result;
}

my %relops = map {; "op$_" => 1 } qw(eq ne gt lt ge le == != < > >= <= =~ !~);

sub _parse_rel {
  my ($self, $tok) = @_;

  my $result = $self->_parse_additive($tok);
  my $nexttype = $tok->peektype;
  while ($relops{$nexttype}) {
    my $op = $tok->get;
    my $other = $self->_parse_additive($tok);
    $result = [ substr($nexttype, 2), $result, $other ];
    $nexttype = $tok->peektype;
  }
  return $result;
}

sub _parse_additive {
  my ($self, $tok) = @_;

  my $result = $self->_parse_mult($tok);
  my $nexttype = $tok->peektype;
  while ($nexttype eq 'op+' || $nexttype eq 'op-' || $nexttype eq 'op_') {
    my $op = $tok->get;
    my $other = $self->_parse_mult($tok);
    $result = [ $ops{$nexttype}, $result, $other ];
    $nexttype = $tok->peektype;
  }
  return $result;
}

sub _parse_mult {
  my ($self, $tok) = @_;

  my $result = $self->_parse_prefix($tok);
  my $nexttype = $tok->peektype;
  while ($nexttype eq 'op*' || $nexttype eq 'op/'
	 || $nexttype eq 'div' || $nexttype eq 'mod') {
    my $op = $tok->get;
    my $other = $self->_parse_prefix($tok);
    $result = [ $ops{$op->[0]}, $result, $other ];
    $nexttype = $tok->peektype;
  }
  return $result;
}

sub _parse_prefix {
  my ($self, $tok) = @_;

  my $nexttype = $tok->peektype('TERM');
  if ($nexttype eq 'op(') {
    $tok->get;
    my $r = $self->_parse_expr($tok);
    my $close = $tok->get;
    unless ($close->[0] eq 'op)') {
      die [ error => "Expected ')' but found $close->[0]" ];
    }
    return $r;
  }
  elsif ($nexttype eq 'op-') {
    $tok->get;
    return [ uminus => $self->_parse_prefix($tok) ];
  }
  elsif ($nexttype eq 'op+') {
    $tok->get;
    return $self->_parse_prefix($tok);
  }
  elsif ($nexttype eq 'op!' || $nexttype eq 'opnot') {
    $tok->get;
    return [ not => $self->_parse_prefix($tok) ];
  }
  else {
    return $self->_parse_call($tok);
  }
}

sub _parse_list {
  my ($self, $tok) = @_;

  $tok->peektype eq 'op)'
    and return [];

  my @list;
  push @list, $self->_parse_expr($tok);
  my $peek = $tok->peektype;
  while ($peek eq 'op,' || $peek eq '..') {
    $tok->get;
    if ($peek eq '..') {
      my $start = pop @list;
      $start->[0] ne 'range'
	or die [ error => "Can't use a range as the start of a range" ];
      my $end = $self->_parse_expr($tok);
      push @list, [ range => $start, $end ];
    }
    else {
      push @list, $self->_parse_expr($tok);
    }
    $peek = $tok->peektype;
  }

  return \@list;
}

sub _parse_paren_list {
  my ($self, $tok, $what) = @_;

  my $open = $tok->get;
  $open->[0] eq 'op('
    or die [ error => "Expected '(' for $what but found $open->[0]" ];
  my $list = $self->_parse_list($tok);
  my $close = $tok->get;
  $close->[0] eq 'op)'
    or die [ error => "Expected ')' for $what but found $close->[0]" ];

  return $list;
}

sub _parse_call {
  my ($self, $tok) = @_;

  my $result = $self->_parse_postfix($tok);
  my $next = $tok->peektype;
  while ($next eq 'op.' || $next eq 'op[') {
    if ($next eq 'op.') {
      $tok->get;
      my $name = $tok->get;
      $name->[0] eq 'id'
	or die [ error => "Expected method name after '.'" ];
      my $list = [];
      if ($tok->peektype eq 'op(') {
	$list = $self->_parse_paren_list($tok, "method");
      }
      $result = [ call => $name->[2], $result, $list ];
    }
    elsif ($next eq 'op[') {
      $tok->get;
      my $index = $self->_parse_expr($tok);
      my $close = $tok->get;
      $close->[0] eq 'op]'
	or die [ error => "Expected list end ']' but got $close->[0]" ];
      $result = [ subscript => $result, $index ];
    }
    $next = $tok->peektype;
  }

  return $result;
}

sub _parse_postfix {
  my ($self, $tok) = @_;

  return $self->_parse_primary($tok);
}

sub _parse_primary {
  my ($self, $tok) = @_;

  my $t = $tok->get('TERM');
  if ($t->[0] eq 'str' || $t->[0] eq 'num') {
    return [ const => $t->[2] ];
  }
  elsif ($t->[0] eq 'id') {
    return [ var => $t->[2] ];
  }
  elsif ($t->[0] eq 'op[') {
    my $list = $self->_parse_list($tok);
    my $close = $tok->get;
    $close->[0] eq 'op]'
      or die [ error => "Expected ] but got $close->[0]" ];
    return [ list => $list ];
  }
  elsif ($t->[0] eq 're') {
    return [ re => $t->[2], $t->[3] ];
  }
  else {
    die [ error => "Expected term but got $t->[0]" ];
  }
}

package Squirrel::Template::Expr::Tokenizer;

use constant TEXT => 0;
use constant QUEUE => 1;

sub new {
  my ($class, $text) = @_;

  return bless [ $text, [] ], $class;
}

my %escapes =
  (
   n => "\n",
   "\\" => "\\",
   t => "\t",
   '"' => '"',
  );

sub get {
  my ($self, $want) = @_;

  my $queue = $self->[QUEUE];
  @$queue
    and return shift @$queue;
  length $self->[TEXT]
    or return;

  $want ||= '';

  if ($want ne 'TERM' &&
	 $self->[TEXT] =~ s/\A(\s*(div|mod|\.\.|and|or)\s*)//) {
    push @$queue, [ $2 => $1 ];
  }
  elsif ($self->[TEXT] =~ s/\A(\s*(0x[0-9A-Fa-f]+)\s*)//) {
    push @$queue, [ num => $1, oct $2 ];
  }
  elsif ($self->[TEXT] =~ s/\A(\s*(0b[01]+)\s*)//) {
    push @$queue, [ num => $1, oct $2 ];
  }
  elsif ($self->[TEXT] =~ s/\A(\s*0o([0-7]+)\s*)//) {
    push @$queue, [ num => $1, oct $2 ];
  }
  elsif ($self->[TEXT] =~ s/\A(\s*((?:\.[0-9]+|[0-9]+(?:\.[0-9]*)?)(?:[Ee][+-]?[0-9]+)?)\s*)//) {
    push @$queue, [ num => $1, $2 ];
  }
  elsif ($want eq 'TERM' &&
	 $self->[TEXT] =~ s!\A(\s*/((?:[^/\\]|\\.)+)/([ismx]*\s)?\s*)!!) {
    push @$queue, [ re => $1, $2, $3 || "" ];
  }
  elsif ($self->[TEXT] =~ s/\A(\s*(not|eq|ne|le|lt|ge|gt|<=|>=|[!=]\=|\=\~|[_\?:,\[\]\(\)<>=!.*\/+-])\s*)//) {
    push @$queue, [ "op$2" => $1 ];
  }
  elsif ($self->[TEXT] =~ s/\A(\s*([A-Za-z_][a-zA-Z_0-9]*)\s*)//) {
    push @$queue, [ id => $1, $2 ];
  }
  elsif ($self->[TEXT] =~ s/\A(\s*\"((?:[^"\\]|\\["\\nt]|\\x[0-9a-fA-F]{2}|\\x\{[0-9a-fA-F]+\}|\\N\{[A-Za-z0-9 ]+\})*)\"\s*)//) {
    my $orig = $1;
    my $str = _process_escapes($2);
    push @$queue, [ str => $1, $str ];
  }
  elsif ($self->[TEXT] =~ s/\A(\s*\'([^\']*)\'\s*)//) {
    push @$queue, [ str => $1, $2 ];
  }
  else {
    die [ error => "Unknown token '$self->[TEXT]'" ];
  }

  unless (length $self->[TEXT]) {
    push @$queue, [ eof => "" ];
  }

  return shift @$queue;
}

sub unget {
  my ($self, $tok) = @_;

  unshift @{$self->[QUEUE]}, $tok;
}

sub peek {
  my ($self, $what) = @_;

  unless (@{$self->[QUEUE]}) {
    my $t = $self->get($what)
      or return;
    unshift @{$self->[QUEUE]}, $t;
  }

  return $self->[QUEUE][0];
}

sub peektype {
  my ($self, $what) = @_;

  return $self->peek($what)->[0];
}

sub _process_escapes {
  my ($str) = @_;

  $str =~
    s(
      \\([nt\\\"])
       |
	 \\x\{([0-9A-Fa-f]+)\}
       |
	 \\x([0-9A-Fa-f]{2})
       |
	 \\N\{([A-Za-z0-9\ ]+)\}
    )(
      $1 ? $escapes{$1} :
      $2 ? chr(hex($2)) :
      $3 ? chr(hex($3)) :
      _vianame($4)
     )gex;

  return $str;
}

my $charnames_loaded;
sub _vianame {
  my ($name, $errors) = @_;

  require charnames;
  my $code = charnames::vianame($name);
  unless (defined $code) {
    die [ error => "Unknown \\N name '$name'" ];
  }
  return chr($code);
}

1;
