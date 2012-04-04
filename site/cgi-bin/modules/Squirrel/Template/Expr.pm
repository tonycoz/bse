package Squirrel::Template::Expr;
use strict;

our $VERSION = "1.002";

package Squirrel::Template::Expr::Eval;
use Scalar::Util ();
use Squirrel::Template::Expr::WrapScalar;
use Squirrel::Template::Expr::WrapHash;
use Squirrel::Template::Expr::WrapArray;
use Squirrel::Template::Expr::WrapCode;
use Squirrel::Template::Expr::WrapClass;

use constant TMPL => 0;

sub new {
  my ($class, $templater) = @_;

  return bless [ $templater ], $class;
}

sub _wrapped {
  my ($self, $val) = @_;

  if (ref($val)) {
    if (Scalar::Util::blessed($val)) {
      return $val;
    }
    else {
      my $type = Scalar::Util::reftype($val);
      if ($type eq "ARRAY") {
	return Squirrel::Template::Expr::WrapArray->new($val);
      }
      elsif ($type eq "HASH") {
	return Squirrel::Template::Expr::WrapHash->new($val);
      }
      elsif ($type eq "CODE") {
	return Squirrel::Template::Expr::WrapCode->new($val);
      }
    }
  }
  else {
    return Squirrel::Template::Expr::WrapScalar->new($val);
  }
}

sub _process_var {
  return $_[0][TMPL]->get_var($_[1][1]);
}

sub _process_add {
  return $_[0]->process($_[1][1]) + $_[0]->process($_[1][2]);
}

sub _process_subtract {
  return $_[0]->process($_[1][1]) - $_[0]->process($_[1][2]);
}

sub _process_mult {
  return $_[0]->process($_[1][1]) * $_[0]->process($_[1][2]);
}

sub _process_fdiv {
  return $_[0]->process($_[1][1]) / $_[0]->process($_[1][2]);
}

sub _process_div {
  return int($_[0]->process($_[1][1]) / $_[0]->process($_[1][2]));
}

sub _process_mod {
  return $_[0]->process($_[1][1]) % $_[0]->process($_[1][2]);
}

# string relops
sub _process_eq {
  return $_[0]->process($_[1][1]) eq $_[0]->process($_[1][2]);
}

sub _process_ne {
  return $_[0]->process($_[1][1]) ne $_[0]->process($_[1][2]);
}

sub _process_gt {
  return $_[0]->process($_[1][1]) gt $_[0]->process($_[1][2]);
}

sub _process_lt {
  return $_[0]->process($_[1][1]) lt $_[0]->process($_[1][2]);
}

sub _process_ge {
  return $_[0]->process($_[1][1]) ge $_[0]->process($_[1][2]);
}

sub _process_le {
  return $_[0]->process($_[1][1]) le $_[0]->process($_[1][2]);
}

# number relops
sub _process_neq {
  return $_[0]->process($_[1][1]) == $_[0]->process($_[1][2]);
}

sub _process_nne {
  return $_[0]->process($_[1][1]) != $_[0]->process($_[1][2]);
}

sub _process_ngt {
  return $_[0]->process($_[1][1]) > $_[0]->process($_[1][2]);
}

sub _process_nlt {
  return $_[0]->process($_[1][1]) < $_[0]->process($_[1][2]);
}

sub _process_nge {
  return $_[0]->process($_[1][1]) >= $_[0]->process($_[1][2]);
}

sub _process_nle {
  return $_[0]->process($_[1][1]) <= $_[0]->process($_[1][2]);
}

sub _process_match {
  return $_[0]->process($_[1][1]) =~ $_[0]->process($_[1][2]);
}

sub _process_notmatch {
  return $_[0]->process($_[1][1]) !~ $_[0]->process($_[1][2]);
}

sub _process_cond {
  return $_[0]->process($_[1][1]) ? $_[0]->process($_[1][2]) : $_[0]->process($_[1][3]);
}

sub _process_uminus {
  return - ($_[0]->process($_[1][1]));
}

sub _process_concat {
  return $_[0]->process($_[1][1]) . $_[0]->process($_[1][2]);
}

sub _process_const {
  return $_[1][1];
}

sub _process_call {
  my ($self, $node, $ctx) = @_;

  $ctx ||= "";

  my $val = $self->process($node->[2]);
  my $args = $self->process_list($node->[3]);
  my $method = $node->[1];
  if (Scalar::Util::blessed($val)
      && !$val->isa("Squirrel::Template::Expr::WrapBase")) {
    $val->can($method)
      or die [ error => "No such method $method" ];
    if ($val->can("restricted_method")) {
      $val->restricted_method($method)
	and die [ error => "method $method is restricted" ];
    }
    return $ctx && $ctx eq 'LIST' ? $val->$method(@$args)
      : scalar($val->$method(@$args));
  }
  else {
    my $wrapped = $self->_wrapped($val);
    return $wrapped->call($method, $args, $ctx);
  }
}

sub _process_list {
  my ($self, $node) = @_;

  return $self->process_list($node->[1], 'LIST');
}

sub _process_range {
  my ($self, $node, $ctx) = @_;

  my $start = $self->process($node->[1]);
  my $end = $self->process($node->[2]);

  return $ctx eq 'LIST' ? ( $start .. $end ) : [ $start .. $end ];
}

sub _process_hash {
  my ($self, $node) = @_;

  my %result;
  for my $pair (@{$node->[1]}) {
    my $key = $self->process($pair->[0]);
    my $value = $self->process($pair->[1]);
    $result{$key} = $value;
  }

  return \%result;
}

sub _process_subscript {
  my ($self, $node) = @_;

  my $list = $self->process($node->[1]);
  my $index = $self->process($node->[2]);
  Scalar::Util::blessed($list)
      and die [ error => "Cannot subscript an object" ];
  my $type = Scalar::Util::reftype($list);
  if ($type eq "HASH") {
    return $list->{$index};
  }
  elsif ($type eq "ARRAY") {
    return $list->[$index];
  }
  else {
    die [ error => "Cannot subscript a $type" ];
  }
}

sub _process_not {
  return !$_[0]->process($_[1][1]);
}

sub _process_or {
  return $_[0]->process($_[1][1]) || $_[0]->process($_[1][2]);
}

sub _process_and {
  return $_[0]->process($_[1][1]) && $_[0]->process($_[1][2]);
}

sub process {
  my ($self, $node, $ctx) = @_;

  my $method = "_process_$node->[0]";
  $self->can($method) or die "No handler for $node->[0]";
  return $self->$method($node, $ctx);
}

sub process_list {
  my ($self, $list) = @_;

  return [ map $self->process($_, 'LIST'), @$list ];
}

package Squirrel::Template::Expr::Parser;

sub new {
  my ($class) = @_;

  return bless {}, $class;
}

sub parse {
  my ($self, $text) = @_;

  my $tokenizer = Squirrel::Template::Expr::Tokenizer->new($text);
  my $result = $self->_parse_expr($tokenizer);

  my $last = $tokenizer->get;
  unless ($last->[0] eq 'eof') {
    die [ error => "Expected eof but found $last->[0]" ];
  }

  return $result;
}

sub parse_tokens {
  my ($self, $tokenizer) = @_;

  return $self->_parse_expr($tokenizer);
}

sub _parse_expr {
  my ($self, $tok) = @_;

  return $self->_parse_cond($tok);
}

my %ops =
  (
   "op+" => "add",
   "op-" => "subtract",
   "op*" => "mult",
   "op/" => "fdiv",
   "div" => "div",
   "mod" => "mod",
   "op_" => "concat",

   "opeq" => "eq",
   "opne" => "ne",
   "oplt" => "lt",
   "opgt" => "gt",
   "ople" => "le",
   "opge" => "ge",

   "op==" => "neq",
   "op!=" => "nne",
   "op<" => "nlt",
   "op>" => "ngt",
   "op<=" => "nle",
   "op>=" => "nge",
   'op=~' => "match",
   'op!~' => "notmatch",
  );

sub _parse_cond {
  my ($self, $tok) = @_;

  my $result = $self->_parse_or($tok);
  if ($tok->peektype eq 'op?') {
    $tok->get;
    my $true = $self->_parse_or($tok);
    my $colon = $tok->get;
    $colon->[0] eq 'op:'
      or die [ error => "Expected : for ? : operator but found $tok->[1]" ];
    my $false = $self->_parse_or($tok);

    $result = [ cond => $result, $true, $false ];
  }

  return $result;
}

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
    $result = [ $ops{$nexttype}, $result, $other ];
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
  elsif ($t->[0] eq 're') {
    my $str = $t->[2];
    my $opts = $t->[3];
    my $sub = eval "sub { my \$str = shift; qr/\$str/$opts; }";
    my $re;
    $sub and $re = eval { $sub->($str) };
    $re
      or die [ error => "Cannot compile /$t->[2]/$opts: $@" ];
    return [ const => $re ];
  }
  elsif ($t->[0] eq 'id') {
    return [ var => $t->[2] ];
  }
  elsif ($t->[0] eq 'op[') {
    my $list = [];
    if ($tok->peektype ne 'op]') {
      $list = $self->_parse_list($tok);
    }
    my $close = $tok->get;
    $close->[0] eq 'op]'
      or die [ error => "Expected ] but got $close->[0]" ];
    return [ list => $list ];
  }
  elsif ($t->[0] eq 'op{') {
    my @pairs;
    if ($tok->peektype eq 'op}') {
      $tok->get; # discard '}'
    }
    else {
      my $next;
      do {
	my $key = $self->_parse_additive($tok);
	my $colon = $tok->get;
	$colon->[0] eq 'op:'
	  or die [ error => "Expected : in hash but found $colon->[1]" ];
	my $value = $self->_parse_expr($tok);
	push @pairs, [ $key, $value ];
      } while ($next = $tok->get and $next->[0] eq 'op,');
      $next->[0] eq 'op}'
	or die [ error => "Expected , or } but found $tok->[1]" ];
    }

    return [ hash => \@pairs ];
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
  elsif ($self->[TEXT] =~ s/\A(\s*(not|eq|ne|le|lt|ge|gt|<=|>=|[!=]\=|\=\~|[_\?:,\[\]\(\)<>=!.*\/+\{\};-])\s*)//) {
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
