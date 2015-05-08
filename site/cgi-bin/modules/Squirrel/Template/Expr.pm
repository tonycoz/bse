package Squirrel::Template::Expr;
use strict;

our $VERSION = "1.016";

package Squirrel::Template::Expr::Eval;
use Scalar::Util ();
use Squirrel::Template::Expr::WrapScalar;
use Squirrel::Template::Expr::WrapHash;
use Squirrel::Template::Expr::WrapArray;
use Squirrel::Template::Expr::WrapCode;
use Squirrel::Template::Expr::WrapClass;

use constant TMPL => 0;
use constant ACTS => 1;

sub new {
  my ($class, $templater, $acts) = @_;

  return bless [ $templater, $acts ], $class;
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
	return Squirrel::Template::Expr::WrapArray->new($val, $self->[TMPL], undef, $self);
      }
      elsif ($type eq "HASH") {
	return Squirrel::Template::Expr::WrapHash->new($val, $self->[TMPL], undef, $self);
      }
      elsif ($type eq "CODE") {
	return Squirrel::Template::Expr::WrapCode->new($val, $self->[TMPL], undef, $self);
      }
    }
  }
  else {
    return Squirrel::Template::Expr::WrapScalar->new($val, $self->[TMPL], $self->[ACTS], $self);
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

sub _process_undef {
  return undef;
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

sub _process_cmp {
  return $_[0]->process($_[1][1]) cmp $_[0]->process($_[1][2]);
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

sub _process_ncmp {
  return $_[0]->process($_[1][1]) <=> $_[0]->process($_[1][2]);
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

sub _process_block {
  return bless [ $_[1][1], $_[1][2] ], "Squirrel::Template::Expr::Block";
}

sub _do_call {
  my ($self, $val, $args, $method, $ctx) = @_;

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

sub _process_call {
  my ($self, $node, $ctx) = @_;

  $ctx ||= "";

  my $val = $self->process($node->[2]);
  my $args = $self->process_list($node->[3]);
  my $method = $node->[1];

  return $self->_do_call($val, $args, $method, $ctx);
}

sub _process_callvar {
  my ($self, $node, $ctx) = @_;

  $ctx ||= "";

  my $val = $self->process($node->[2]);
  my $args = $self->process_list($node->[3]);
  my $method = $self->[TMPL]->get_var($node->[1]);

  return $self->_do_call($val, $args, $method, $ctx);
}

sub _do_callblock {
  my ($self, $ids, $exprs, $args) = @_;

  my $result;
  my %args;
  @args{@$ids} = @$args;
  $args{_arguments} = $args;
  if (eval { $self->[TMPL]->start_scope("calling block", \%args), 1}) {
    for my $expr (@$exprs) {
      $result = $self->process($expr);
    }
    $self->[TMPL]->end_scope();
  }

  return $result;
}

sub call_function {
  my ($self, $code, $args, $ctx) = @_;

  $ctx ||= "";

  if (Scalar::Util::reftype($code) eq "CODE") {
    return $ctx eq "LIST" ? $code->(@$args) : scalar($code->(@$args));
  }
  elsif (Scalar::Util::blessed($code)
	 && $code->isa("Squirrel::Template::Expr::Block")) {
    return $self->_do_callblock($code->[0], $code->[1], $args);
  }
  else {
    die [ error => "can't call non code as a function" ];
  }
}

sub _process_funccall {
  my ($self, $node, $ctx) = @_;

  my $code = $self->process($node->[1]);
  my $args = $self->process_list($node->[2]);

  return $self->call_function($code, $args, $ctx);
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
   "opcmp" => "cmp",

   "op==" => "neq",
   "op!=" => "nne",
   "op<" => "nlt",
   "op>" => "ngt",
   "op<=" => "nle",
   "op>=" => "nge",
   'op=~' => "match",
   'op!~' => "notmatch",
   'op<=>' => 'ncmp',
  );

sub _parse_cond {
  my ($self, $tok) = @_;

  my $result = $self->_parse_or($tok);
  if ($tok->peektype eq 'op?') {
    $tok->get;
    my $true = $self->_parse_or($tok);
    my $colon = $tok->get;
    $colon->[0] eq 'op:'
      or die [ error => "Expected : for ? : operator but found $colon->[0]" ];
    my $false = $self->_parse_cond($tok);

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

my %relops = map {; "op$_" => 1 } qw(eq ne gt lt ge le cmp == != < > >= <= <=> =~ !~);

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
  if ($nexttype eq 'op-') {
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

  $tok->peektype("TERM") eq 'op)'
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
  while ($next eq 'op.' || $next eq 'op[' || $next eq 'op(') {
    if ($next eq 'op.') {
      $tok->get;
      my $name = $tok->get;
      if ($name->[0] eq "id") {
	my $list = [];
	if ($tok->peektype eq 'op(') {
	  $list = $self->_parse_paren_list($tok, "method");
	}
	$result = [ call => $name->[2], $result, $list ];
      }
      elsif ($name->[0] eq 'op$') {
	# get the real name
	$name = $tok->get;
	$name->[0] eq 'id'
	  or die [ error => "Expected an identifier after .\$ but found $name->[1]" ];
	my $list = [];
	if ($tok->peektype eq 'op(') {
	  $list = $self->_parse_paren_list($tok, "method");
	}
	$result = [ callvar => $name->[2], $result, $list ];
      }
      else {
	die [ error => "Expected a method name or \$var after '.' but found $name->[1]" ];
      }
    }
    elsif ($next eq 'op[') {
      $tok->get;
      my $index = $self->_parse_expr($tok);
      my $close = $tok->get;
      $close->[0] eq 'op]'
	or die [ error => "Expected closing ']' but got $close->[0]" ];
      $result = [ subscript => $result, $index ];
    }
    elsif ($next eq 'op(') {
      my $args = $self->_parse_paren_list($tok, "call");
      $result = [ funccall => $result, $args ];
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
  if ($t->[0] eq 'op(') {
    my $r = $self->_parse_expr($tok);
    my $close = $tok->get;
    unless ($close->[0] eq 'op)') {
      die [ error => "Expected ')' but found $close->[0]" ];
    }
    return $r;
  }
  elsif ($t->[0] eq 'str' || $t->[0] eq 'num') {
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
    if ($t->[2] eq "undef") {
      return [ "undef" ];
    }
    else {
      return [ var => $t->[2] ];
    }
  }
  elsif ($t->[0] eq 'op[') {
    my $list = [];
    if ($tok->peektype ne 'op]') {
      $list = $self->_parse_list($tok);
    }
    my $close = $tok->get;
    $close->[0] eq 'op]'
      or die [ error => "Expected list end ']' but got $close->[0]" ];
    return [ list => $list ];
  }
  elsif ($t->[0] eq 'op{') {
    my $pairs = $self->parse_pairs($tok);
    my $next = $tok->get;
    $next->[0] eq 'op}'
      or die [ error => "Expected , or } but found $next->[1]" ];

    return [ hash => $pairs ];
  }
  elsif ($t->[0] eq 're') {
    return [ re => $t->[2], $t->[3] ];
  }
  elsif ($t->[0] eq 'undef') {
    return [ "undef" ];
  }
  elsif ($t->[0] eq 'blockstart') {
    # @{ idlist: expr; ... }
    # idlist can be empty:
    # @{ : expr; ... }
    # the expr list will become more complex at some point
    my @ids;
    my $nexttype = $tok->peektype;
    if ($nexttype ne 'op:') {
      $nexttype eq 'id'
	or die [ error => "Expected id or : after \@{ but found $nexttype->[0]" ];
      push @ids, $tok->get->[2];
      while ($tok->peektype eq 'op,') {
	$tok->get;
	$tok->peektype eq 'id'
	  or die [ error => "Expected id after , in \@{ but found $nexttype->[0]" ];
	push @ids, $tok->get->[2];
      }
      my $end = $tok->get;
      $end->[0] eq 'op:'
	or die [ error => "Expected :  or , in identifier list in \@{ but found $end->[0]" ];
    }
    else {
      # consume the :
      $tok->get;
    }
    my @exprs;
    push @exprs, $self->_parse_expr($tok);
    while ($tok->peektype eq 'op;') {
      $tok->get;
      push @exprs, $self->_parse_expr($tok);
    }
    $nexttype = $tok->peektype;
    $nexttype eq 'op}'
      or die [ error => "Expected } at end of \@{ but found $nexttype" ];
    # consume the }
    $tok->get;
    return [ block => \@ids, \@exprs ];
  }
  else {
    die [ error => "Expected term but got $t->[0]" ];
  }
}

sub parse_pairs {
  my ($self, $tok) = @_;

  my $nexttype = $tok->peektype;
  if ($nexttype eq 'op}' || $nexttype eq 'eof') {
    return [];
  }
  else {
    my $next;
    my @pairs;
    do {
      my $key;
      if ($tok->peektype eq 'id') {
	my $id = $tok->get;
	if ($tok->peektype eq 'op:') {
	  $key = [ const => $id->[2] ];
	}
	else {
	  $tok->unget($id);
	}
      }
      $key ||= $self->_parse_additive($tok);
      my $colon = $tok->get;
      $colon->[0] eq 'op:'
	or die [ error => "Expected : in hash but found $colon->[1]" ];
      my $value = $self->_parse_expr($tok);
      push @pairs, [ $key, $value ];
    } while ($next = $tok->get and $next->[0] eq 'op,');
    $tok->unget($next);

    return \@pairs;
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
	 $self->[TEXT] =~ s/\A(\s*(div\b|mod\b|\.\.|and\b|or\b)\s*)//) {
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
  elsif ($self->[TEXT] =~ s/\A(\s*(not\b|eq\b|ne\b|le\b|lt\b|ge\b|gt\b|cmp\b|<=>|<=|>=|[!=]\=|\=\~|!~|[\?:,\[\]\(\)<>=!.*\/+\{\};\$-]|_(?![A-Za-z0-9_]))\s*)//) {
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
  elsif ($self->[TEXT] =~ s/\A(\s*\@undef\bs*)//) {
    push @$queue, [ undef => $1 ];
  }
  elsif ($self->[TEXT] =~ s/\A(\s*@\{\s*)//) {
    push @$queue, [ blockstart => $1 ];
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

__END__

=head1 NAME

Squirrel::Template::Expr - expression handling for Squirrel::Template

=head1 SYNOPSIS

  # code that uses it
  my $parser = Squirrel::Template::Expr::Parser->new;

  my $expr = $parser->parse($expr_text);

  my $tokens = Squirrel::Template::Expr::Tokenizer->new($expr_text);

  my $expr = $parser->parse_tokens($tokenizer);
  # and possibly process more tokens here

  my $eval = Squirrel::Template::Expr::Parser->new($templater);

  my $value = $eval->process($expr);
  my $value = $eval->process($expr, "LIST");

  my $arrayref = $eval->process(\@exprs);

  # Expressions

  <:= somevalue + 10 :>
  <:.if somevalue == 10 :>

=head1 DESCRIPTION

Squirrel::Template::Expr provides expression parsing and evaluation
for newer style tags for L<Squirrel::Template>.

=head1 EXPRESSION SYNTAX

=head2 Operators

Listed highest precedence first.

=over

=item *

C<<[ I<list> ]>>, C<<{ I<key>:I<value>, ... }>>, literals

C<<[ I<list> ]>> allows you to build lists objects.  Within C<[ ... ]>
you can use the C<..> operator to produce a list of numerically or
alphabetically ascending values per Perl's magic increment.

eg.

  [ "a", "c" .. "z" ]
  [ 1 .. 10 ]

Method calls within C<<[ ... ]>> are done in perl's list context.

C<<{ ... }>> allows you to build hash objects.

eg.

  { "somekey":somevariable, somekeyinvar:"somevalue" }

See L</Literals> for literals

=item *

method calls - methods are called as:

  object.method;

or

  object.method(arguments)

and may be chained.

Virtual methods are defined for hashes, arrays and scalars, see
L<Squirrel::Template::Expr::WrapHash>,
L<Squirrel::Template::Expr::WrapArray>,
L<Squirrel::Template::Expr::WrapScalar>,
L<Squirrel::Template::Expr::WrapCode> and
L<Squirrel::Template::Expr::WrapClass>.

=item *

function calls - functions are called as:

  somevar();

or

  somevar(arguments);

or any other expression that doesn't look like a method call:

  somehash.get["foo"]();

=item *

unary -, unary +, unary !, unary not

=item *

* / div mod - simple arithmetic operators.  C<div> returns the integer
portion of dividing the first operand by the second.  C<mod> returns
the remainder of integer division.

=item *

+ - _ - arithmetic addition and subtraction. C<_> does string
concatenation.

=item *

eq ne le lt ge gt == != > < >= <= =~ !~ - relational operators as per
Perl.

=item *

and - boolean and, with shortcut.

=item *

or - boolean or, with shortcut.

=item *

Conditional (C<< I<cond> ? I<true> : I<false> >>) - return the value
of I<true> or I<false> depending on I<cond>.

=back

=head2 Literals

Numbers can be represented in several formats:

=over

=item *

simple decimal - C<100>, C<3.14159>, C<1e10>.

=item *

hex - C<0x64>

=item *

octal - C<0o144>

=item *

binary - C<0b1100100>

=item *

an undefined value - C<@undef>

=item *

blocks - C<< @{ I<idlist> : I<exprlist> } >> where C<< I<idlist> >> is
a comma separated list of local variables that arguments are assigned
to, and I<exprlist> is a semi-colon separated list of expressions.
The block literal can be called as if it's a function, or supplied to
methods like the array grep() method.

=back

Strings can be either " or ' delimited.

Simple quote delimited strings allow no escaping, and may not contain
single quotes.  The contents are treated literally.

Double quoted strings allow escaping as follows:

=over

=item *

Any of C<\">, C<\n>, C<\\>, C<\t> are treated as in C or perl,
replaced with double quote, newline, backslash or tab respectively.

=item *

C<<\x{I<hex-digits>}>> is replaced with the unicode code-point
indicated by the hex number.

=item *

C<< \xI<hex-digit>I<hex-digit> >> is replaced by the unicode
code-point indicated by the 2-digit hex number.

=item *

C<< \N{ I<unicode-character-name> } >> is replaced by the unicode
character named.

=back

=head1 Squirrel::Template::Expr::Parser

Squirrel::Template::Expr::Parser provides parsing for expressions.

=head1 Methods

=over

=item new()

Create a new parser object.

=item parse($text)

Parse C<$text> as an expression.  Parsing must reach the end of the
text or an exception will be thrown.

=item parse_tokens($tokenizer)

Process tokens from C<$tokenizer>, a
L</Squirrel::Template::Expr::Tokenizer> object.  The caller can call
these method several times with the same C<$tokenizer> to parse
components of a statement, and should ensure the eof token is visible
after the final component.

=back

=head1 Squirrel::Template::Expr::Tokenizer

Split text into tokens.  Token parsing is occasionally context
sensitive.

=head2 Methods

=over

=item new($text)

Create a new tokenizer for parsing C<$text>.

=item get()

=item get($context)

Retrieve a token from the stream, consuming it.  If a term is expected
$context should be set to C<'TERM'>.

=item unget()

Push a token back into the stream.

=item peek()

=item peek($context)

Retrieve the next token from the stream without consuming it.

=item peektype()

=item peektype($context)

Retrieve the type of the next token from the stream without consuming
it.

=back

=head1 Squirrel::Template::Expr::Eval

Used to evaluate an expression returned by
Squirrel::Template::Expr::parse().

=head2 Methods

=over

=item new($templater)

Create a new evaluator.  C<$templater> should be a
L<Squirrel::Template> object.

=back

=head1 SEE ALSO

L<Squirrel::Template>

=head1 AUTHOR

Tony Cook <tony@develop-help.com>

=cut
