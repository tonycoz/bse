package Squirrel::Template::Parser;
use strict;
use Squirrel::Template::Constants qw(:token :node);

our $VERSION = "1.019";

use constant TOK => 0;
use constant TMPLT => 1;
use constant ERRORS => 2;

use constant TRACE => 0;

sub new {
  my ($class, $tokenizer, $templater) = @_;

  return bless [ $tokenizer, $templater, [] ], $class;
}

sub parse {
  my ($self) = @_;

  my @results;

  while (1) {
    push @results, $self->_parse_content;

    my $tok = $self->[TOK]->get;

    if (!$tok) {
      die "Internal error: Unexpected end of tokens\n";
    }

    last if $tok->[TOKEN_TYPE] eq 'eof';

    push @results, $self->_error_mod($tok, "Expected eof but found $tok->[TOKEN_TYPE]");
  }

  return @results > 1 ? $self->_comp(@results) : $results[0];
}

sub _parse_content {
  my ($self) = @_;

  my @result;
  my $token;
  TOKEN:
  while (my $token = $self->[TOK]->get) {
    my $type = $token->[TOKEN_TYPE];
    print STDERR "NEXT: $type\n" if TRACE;
    if ($type eq 'content' || $type eq 'tag' || $type eq 'wraphere') {
      push @result, $token;
    }
    else {
      my $method = "_parse_$type";
      if ($self->can($method)) {
	push @result, $self->$method($token);
      }
      else {
	$self->[TOK]->unget($token);
	last TOKEN;
      }
    }
  }

  if (@result > 1) {
    return $self->_comp(@result);
  }
  elsif (@result) {
    return $result[0];
  }
  else {
    return $self->_empty($self->[TOK]->peek);
  }
}

sub _empty {
  my ($self, $tok) = @_;

  return [ empty => "", $tok->[TOKEN_LINE], $tok->[TOKEN_FILENAME] ];
}

sub _error {
  my ($self, $tok, $message) = @_;

  print STDERR "ERROR: $message\n" if TRACE;

  my $error = [ error => "", $tok->[TOKEN_LINE], $tok->[TOKEN_FILENAME], $message ];
  push @{$self->[ERRORS]}, $error;

  return $error;
}

# returns the token transformed into an error message, ie the token is being replaced

sub _error_mod {
  my ($self, $tok, $message) = @_;

  my $error = [ error => $tok->[TOKEN_ORIG], $tok->[TOKEN_LINE], $tok->[TOKEN_FILENAME], $message ];
  push @{$self->[ERRORS]}, $error;

  return $error;
}

sub _dummy {
  my ($self, $base, $type, $orig) = @_;

  return [ $type => $orig, $base->[TOKEN_LINE], $base->[TOKEN_FILENAME] ];
}

sub _comp {
  my ($self, @parts) = @_;

  my @result = ( comp => "", $parts[0][TOKEN_LINE], $parts[0][TOKEN_FILENAME] );

  for my $part (@parts) {
    if ($part->[0] eq "comp") {
      push @result, @{$part}[4 .. $#$part];
    }
    else {
      push @result, $part;
    }
  }

  return \@result;
}

sub _parse_expr {
  my ($self, $expr) = @_;

  my $parser = Squirrel::Template::Expr::Parser->new;
  my $parsed;
  local $SIG{__DIE__};
  if (eval { $parsed = $parser->parse($expr->[TOKEN_EXPR_EXPR]); 1 }) {
    $expr->[NODE_EXPR_EXPR] = $parsed;
    $expr->[NODE_EXPR_FORMAT] ||= $self->[TMPLT]{def_format};
    return $expr;
  }
  elsif (ref $@) {
    return $self->_error($expr, $@->[1]);
  }
  else {
    return $self->_error($expr, $@);
  }
}

sub _parse_stmt {
  my ($self, $stmt) = @_;

  my $parser = Squirrel::Template::Expr::Parser->new;
  my $tokens = Squirrel::Template::Expr::Tokenizer->new($stmt->[TOKEN_EXPR_EXPR]);
  my @list;
  my $parsed;
  local $SIG{__DIE__};
  my $good = eval {
    push @list, $parser->parse_tokens($tokens);
    while ($tokens->peektype eq "op;") {
      $tokens->get;
      push @list, $parser->parse_tokens($tokens);
    }
    $tokens->peektype eq "eof"
      or die [ error => "Expected ; or end, but found ".$tokens->peektype ];
    1;
  };
  if ($good) {
    $stmt->[NODE_EXPR_EXPR] = \@list;
    return $stmt;
  }
  elsif (ref $@) {
    return $self->_error($stmt, $@->[1]);
  }
  else {
    return $self->_error($stmt, $@);
  }
}

sub _parse_set {
  my ($self, $set) = @_;

  my $parser = Squirrel::Template::Expr::Parser->new;
  my $parsed;
  local $SIG{__DIE__};
  if (eval { $parsed = $parser->parse($set->[TOKEN_SET_EXPR]); 1 }) {
    $set->[NODE_SET_VAR] = [ split /\./, $set->[TOKEN_SET_VAR] ];
    $set->[NODE_SET_EXPR] = $parsed;
    return $set;
  }
  elsif (ref $@) {
    return $self->_error($set, $@->[1]);
  }
  else {
    return $self->_error($set, $@);
  }
}

sub _parse_if {
  my ($self, $if) = @_;

  my $true = $self->_parse_content;
  my $or = $self->[TOK]->get;
  my $eif;
  my $false;
  my @errors;
  if ($or->[TOKEN_TYPE] eq 'or') {
    if ($or->[TOKEN_TAG_NAME] ne "" && $or->[TOKEN_TAG_NAME] ne $if->[TOKEN_TAG_NAME]) {
      push @errors, $self->_error($or, "'or' or 'eif' for 'if $if->[TOKEN_TAG_NAME]' starting $if->[TOKEN_FILENAME]:$if->[TOKEN_LINE] expected but found 'or $or->[TOKEN_TAG_NAME]'");
    }
    $false = $self->_parse_content;

    $eif = $self->[TOK]->get;
    if ($eif->[TOKEN_TYPE] eq 'eif') {
      if ($eif->[TOKEN_TAG_NAME] ne "" && $eif->[TOKEN_TAG_NAME] ne $if->[TOKEN_TAG_NAME]) {
	push @errors, $self->_error($or, "'eif' for 'if $if->[TOKEN_TAG_NAME]' starting $if->[TOKEN_FILENAME]:$if->[TOKEN_LINE] expected but found 'eif $eif->[TOKEN_TAG_NAME]'");
      }
      # fall through
    }
    else {
      push @errors, $self->_error($eif, "Expected 'eif' tag for if starting $if->[TOKEN_FILENAME]:$if->[TOKEN_LINE] but found $eif->[TOKEN_TYPE]");
      $self->[TOK]->unget($eif);
      $eif = $self->_dummy($eif, eif => "<:eif:>");
    }
  }
  elsif ($or->[TOKEN_TYPE] eq 'eif') {
    if ($or->[TOKEN_TAG_NAME] ne "" && $or->[TOKEN_TAG_NAME] ne $if->[TOKEN_TAG_NAME]) {
      push @errors, $self->_error($or, "'or' or 'eif' for 'if $if->[TOKEN_TAG_NAME]' starting $if->[TOKEN_FILENAME]:$if->[TOKEN_LINE] expected but found 'eif $or->[TOKEN_TAG_NAME]'");
    }

    $eif = $or;
    $or = $false = $self->_empty($or);
  }
  else {
    push @errors, $self->_error($or, "Expected 'or' or 'eif' tag for if starting $if->[TOKEN_FILENAME]:$if->[TOKEN_LINE] but found $or->[TOKEN_TYPE]");
    $self->[TOK]->unget($or);
    $or = $false = $self->_empty($or);
    $eif = $self->_dummy($or, eif => "");
  }
  @{$if}[NODE_TYPE, NODE_COND_TRUE, NODE_COND_FALSE, NODE_COND_OR, NODE_COND_EIF] = ( "cond", $true, $false, $or, $eif );
  if (@errors) {
    return $self->_comp($if, @errors);
  }
  else {
    return $if;
  }
}

sub _parse_ifnot {
  my ($self, $ifnot) = @_;

  my $true = $self->_parse_content;
  my $eif = $self->[TOK]->get;
  my @errors;
  if ($eif->[TOKEN_TYPE] eq 'eif') {
    if ($eif->[TOKEN_TAG_NAME] ne "" && $eif->[TOKEN_TAG_NAME] ne $ifnot->[TOKEN_TAG_NAME]) {
      push @errors, $self->_error($eif, "'eif' for 'if !$ifnot->[TOKEN_TAG_NAME]' starting $ifnot->[TOKEN_FILENAME]:$ifnot->[TOKEN_LINE] expected but found 'eif $eif->[TOKEN_TAG_NAME]'");
    }
    # fall through
  }
  else {
    push @errors, $self->_error($eif, "Expected 'eif' tag for if ! starting $ifnot->[TOKEN_FILENAME]:$ifnot->[TOKEN_LINE] but found $eif->[TOKEN_TYPE]");
    $self->[TOK]->unget($eif);
    $eif = $self->_dummy($eif, eif => "<:eif:>");
  }

  @{$ifnot}[NODE_TYPE, NODE_COND_TRUE, NODE_COND_EIF] = ( "condnot", $true, $eif );
  if (@errors) {
    return $self->_comp($ifnot, @errors);
  }
  else {
    return $ifnot;
  }
}

sub _parse_itbegin {
  my ($self, $start) = @_;

  my $name = $start->[TOKEN_TAG_NAME];
  my $loop = $self->_parse_content;
  my $septok = $self->[TOK]->get;
  my $endtok;
  my $sep;
  my @errors;
  if ($septok->[TOKEN_TYPE] eq 'itsep') {
    if ($septok->[TOKEN_TAG_NAME] ne $name) {
      push @errors, $self->_error($septok, "Expected 'iterator separator $name' for 'iterator begin $name' at $start->[TOKEN_FILENAME]:$start->[TOKEN_LINE] but found 'iterator separator $septok->[TOKEN_TAG_NAME]'");
    }
    $sep = $self->_parse_content;
    $endtok = $self->[TOK]->get;
    if ($endtok->[TOKEN_TYPE] eq 'itend') {
      if ($endtok->[TOKEN_TAG_NAME] ne $name) {
	push @errors, $self->_error($endtok, "Expected 'iterator end $name' for 'iterator begin $name' at $start->[TOKEN_FILENAME]:$start->[TOKEN_LINE] but found 'iterator end $endtok->[TOKEN_TAG_NAME]'");
      }
    }
    else {
      push @errors, $self->_error($endtok, "Expected 'iterator end $name' for 'iterator begin $name' at $start->[TOKEN_FILENAME]:$start->[TOKEN_LINE] but found $endtok->[TOKEN_TYPE]");
      $self->[TOK]->unget($endtok);
      $endtok = $self->_dummy($endtok, "itend", "<:iterator end $name:>");
    }
  }
  elsif ($septok->[TOKEN_TYPE] eq 'itend') {
    $sep = $self->_empty($septok);
    if ($septok->[TOKEN_TAG_NAME] ne $name) {
      push @errors, $self->_error($septok, "Expected 'iterator end $name' for 'iterator begin $start->[TOKEN_TAG_NAME]' at $start->[TOKEN_FILENAME]:$start->[TOKEN_LINE] but found 'iterator end $septok->[TOKEN_TAG_NAME]'");
    }
    $endtok = $septok;
    $septok = $self->_empty($endtok);
  }
  else {
    push @errors, $self->_error($septok, "Expected 'iterator separator $name' or 'iterator end $name' for 'iterator begin $name' at $start->[TOKEN_FILENAME]:$start->[TOKEN_LINE] but found $septok->[TOKEN_TYPE]");
    $self->[TOK]->unget($septok);
    $sep = $self->_empty($septok);
    $septok = $self->_empty($septok);
    $endtok = $self->_dummy($septok, itend => "<:iterator end $name:>");
  }
  @{$start}[NODE_TYPE, NODE_ITERATOR_LOOP, NODE_ITERATOR_SEPARATOR, NODE_ITERATOR_SEPTOK, NODE_ITERATOR_ENDTOK] =
    ( iterator => $loop, $sep, $septok, $endtok );
  if (@errors) {
    return $self->_comp($start, @errors);
  }
  else {
    return $start;
  }
}

sub _parse_withbegin {
  my ($self, $start) = @_;

  my $name = $start->[TOKEN_TAG_NAME];
  my $loop = $self->_parse_content;
  my $end = $self->[TOK]->get;
  my @errors;
  if ($end->[TOKEN_TYPE] eq 'withend') {
    if ($end->[TOKEN_TAG_NAME] ne $name) {
      push @errors, $self->_error($end, "Expected 'with end $name' for 'with begin $name' at $start->[TOKEN_FILENAME]:$start->[TOKEN_LINE] but found 'with end $end->[TOKEN_TAG_NAME]'");
    }
  }
  else {
    push @errors, $self->_error($end, "Expected 'with end $name' for 'with begin $name' at $start->[TOKEN_FILENAME]:$start->[TOKEN_LINE] but found $end->[TOKEN_TYPE]");
    $self->[TOK]->unget($end);
    $end = $self->_dummy($end, withend => "<:with end $start->[TOKEN_TAG_NAME]:>");
  }
  @{$start}[NODE_TYPE, NODE_WITH_CONTENT, NODE_WITH_END] = ( "with", $loop, $end );
  if (@errors) {
    return $self->_comp($start, @errors);
  }
  else {
    return $start;
  }
}

sub _parse_for {
  my ($self, $for) = @_;

  my $content = $self->_parse_content;
  my $end = $self->[TOK]->get;
  my $error;
  if ($end->[TOKEN_TYPE] eq 'end') {
    if ($end->[TOKEN_END_TYPE] && $end->[TOKEN_END_TYPE] ne 'for') {
      $error = $self->_error($end, "Expected '.end' or '.end for' for .for started $for->[TOKEN_FILENAME]:$for->[TOKEN_LINE] but found '.end $end->[TOKEN_END_TYPE]'");
    }
  }
  else {
    $self->[TOK]->unget($end);
    $error = $self->_error($end, "Expected '.end' for .for started $for->[TOKEN_FILENAME]:$for->[TOKEN_LINE] but found $end->[TOKEN_TYPE]");
    $end = $self->_empty($end);
  }
  my $list_expr;
  my $parser = Squirrel::Template::Expr::Parser->new;
  local $SIG{__DIE__};
  unless (eval { $list_expr = $parser->parse($for->[TOKEN_FOR_EXPR]); 1 }) {
    return $self->_error($for, "Could not parse list for .for: " . (ref $@ ? $@->[0] : $@));
  }
  @{$for}[NODE_FOR_EXPR, NODE_FOR_END, NODE_FOR_CONTENT] =
    ( $list_expr, $end, $content );

  if ($error) {
    return $self->_comp($for, $error);
  }
  else {
    return $for;
  }
}

sub _parse_switch {
  my ($self, $start) = @_;

  my $ignored = $self->_parse_content;
  my $error;
  my @cases;
  my $tok;
  CASE:
  while ($tok = $self->[TOK]->get) {
    if ($tok->[TOKEN_TYPE] eq 'case' || $tok->[TOKEN_TYPE] eq 'casenot') {
      my $case = $self->_parse_content;
      push @cases, [ $tok, $case ];
    }
    elsif ($tok->[TOKEN_TYPE] eq 'endswitch') {
      last CASE;
    }
    else {
      $self->[TOK]->unget($tok);
      $error = $self->_error($tok, "Expected case or endswitch for switch starting $start->[TOKEN_FILENAME]:$start->[TOKEN_LINE] but found $tok->[TOKEN_TYPE]");
      $tok = $self->_dummy($tok, endswitch => "<:endswitch:>");
      last CASE;
    }
  }

  @{$start}[NODE_SWITCH_CASES, NODE_SWITCH_END] = ( \@cases, $tok );

  if ($error) {
    return $self->_comp($start, $error);
  }
  else {
    return $start;
  }
}

sub _parse_wrap {
  my ($self, $start) = @_;

  my $content = $self->_parse_content;
  my $end = $self->[TOK]->get;

  my $error;
  if ($end->[TOKEN_TYPE] eq 'endwrap') {
    # nothing to do
  }
  elsif ($end->[TOKEN_TYPE] eq 'eof') {
    $self->[TOK]->unget($end);
  }
  else {
    $self->[TOK]->unget($end);
    $error = $self->_error($end, "Expected 'endwrap' or eof for wrap started $start->[TOKEN_FILENAME]:$start->[TOKEN_LINE] but found $end->[TOKEN_TYPE]");
  }
  $start->[NODE_WRAP_CONTENT] = $content;

  if ($error) {
    return $self->_comp($start, $error);
  }
  else {
    return $start;
  }
}

sub _parse_ext_wrap {
  my ($self, $wrap) = @_;

  my $content = $self->_parse_content;
  my $end = $self->[TOK]->get;

  # it's not really the filename (yet)
  my $tokens = Squirrel::Template::Expr::Tokenizer->new($wrap->[NODE_WRAP_FILENAME]);

  my @errors;
  my $parser = Squirrel::Template::Expr::Parser->new;
  my $name_expr;
  unless (eval { $name_expr = $parser->parse_tokens($tokens); 1 }) {
    return $self->_error($wrap, "Could not parse expression: ".$@->[1]);
  }

  my @result;
  my $next = $tokens->get;
  my @args;
  if ($next->[0] eq 'op,') {
    unless (eval {
      while ($next->[0] eq 'op,') {
	my $key;
	my $value;
	$key = $parser->parse_tokens($tokens);
	my $colon = $tokens->get;
	$colon->[0] eq 'op:'
	  or die [ error => "Expected : but found $colon->[0]" ];
	$value = $parser->parse_tokens($tokens);
	push @args, [ $key, $value ];
	$next = $tokens->get;
      }

      if ($next->[0] ne 'eof') {
	die [ error => "Expected , or eof but found $next->[0]" ];
      }
      1;
    }) {
      return $self->_error($wrap, ref $@ ? $@->[0] : $@);
    }
  }
  elsif ($next->[0] ne 'eof') {
    push @errors, $self->_error($wrap, "Expected , or end of expression but found $next->[0]");
  }

  if ($end->[TOKEN_TYPE] eq 'end') {
    if ($end->[TOKEN_END_TYPE] && $end->[TOKEN_END_TYPE] ne 'wrap') {
      push @errors, $self->_error($end, "Expected '.end' or '.end wrap' for .wrap started $wrap->[TOKEN_FILENAME]:$wrap->[TOKEN_LINE] but found '.end $end->[TOKEN_END_TYPE]'");
    }
  }
  elsif ($end->[TOKEN_TYPE] eq 'eof') {
    $self->[TOK]->unget($end);
  }
  else {
    $self->[TOK]->unget($end);
    push @errors, $self->_error($end, "Expected '.end', '.end wrap' or eof for .wrap started $wrap->[TOKEN_FILENAME]:$wrap->[TOKEN_LINE] but found $end->[TOKEN_TYPE]");
    $end = $self->_dummy($end, end => "");
  }
  $wrap->[NODE_WRAP_CONTENT] = $content;
  $wrap->[NODE_WRAP_FILENAME] = $name_expr;
  $wrap->[NODE_WRAP_ARGS] = \@args;
  $wrap->[NODE_WRAP_END] = $end;

  if (@errors) {
    return $self->_comp($wrap, @errors);
  }
  else {
    return $wrap;
  }
}

sub _parse_define {
  my ($self, $define) = @_;

  my $content = $self->_parse_content;
  my $end = $self->[TOK]->get;
  my @errors;
  if ($end->[TOKEN_TYPE] eq 'end') {
    if ($end->[TOKEN_END_TYPE] && $end->[TOKEN_END_TYPE] ne 'define') {
      push @errors, $self->_error($end, "Expected '.end' or '.end define' for .define started $define->[TOKEN_FILENAME]:$define->[TOKEN_LINE] but found '.end $end->[TOKEN_END_TYPE]'");
    }
  }
  else {
    $self->[TOK]->unget($end);
    push @errors, $self->_error($end, "Expected '.end' for .define started $define->[TOKEN_FILENAME]:$define->[TOKEN_LINE] but found $end->[TOKEN_TYPE]");
    $end = $self->_empty($end);
  }

  my $text = $define->[NODE_DEFINE_NAME];
  my $name;
  if ($text =~ s(^([^;\s]+))()) {
    $name = $1;
  }
  my $defaults;
  my %seen_args;
  if ($text =~ s/^\s*;\s*// && $text ne "") {
    my $tokens = Squirrel::Template::Expr::Tokenizer->new($text);
    my $parser = Squirrel::Template::Expr::Parser->new;
    $defaults = $parser->parse_pairs($tokens);
    $tokens->peektype eq 'eof'
      or push @errors, $self->_error($end, "Defaults list for .define started $define->[TOKEN_FILENAME]:$define->[TOKEN_LINE] has extra junk");
  }
  $define->[NODE_DEFINE_NAME] = $name;

  @{$define}[NODE_DEFINE_END, NODE_DEFINE_CONTENT, NODE_DEFINE_DEFAULTS] =
    ( $end, $content, $defaults );

  if (@errors) {
    return $self->_comp($define, @errors);
  }
  else {
    return $define;
  }
}

sub _parse_call {
  my ($self, $call) = @_;

  my $tokens = Squirrel::Template::Expr::Tokenizer->new($call->[TOKEN_EXPR_EXPR]);

  my $error;
  my $parser = Squirrel::Template::Expr::Parser->new;
  my $name_expr;
  local $SIG{__DIE__};
  unless (eval { $name_expr = $parser->parse_tokens($tokens); 1 }) {
    return $self->_error($call, "Could not parse expression: ".$@->[1]);
  }

  my @result;
  my $next = $tokens->get;
  my $args = [];
  if ($next->[0] eq 'op,') {
    unless (eval {
      $args = $parser->parse_pairs($tokens);

      if ($tokens->peektype ne 'eof') {
	die [ error => "Expected , or eof but found $next->[0]" ];
      }
      1;
    }) {
      return $self->_error($call, ref $@ ? $@->[0] : $@);
    }
  }
  elsif ($next->[0] ne 'eof') {
    $error = $self->_error($call, "Expected , or end of expression but found $next->[0]");
  }

  @{$call}[NODE_CALL_NAME, NODE_CALL_LIST] = ( $name_expr, $args );

  return $error ? $self->_comp($call, $error) : $call;
}

sub _parse_ext_if {
  my ($self, $if) = @_;

  my @conds;
  my @errors;
  my $content = $self->_parse_content;
  push @conds, [ $if, $content];
  my $next = $self->[TOK]->get;
  while ($next->[TOKEN_TYPE] eq 'ext_elsif') {
    my $content = $self->_parse_content;
    push @conds, [ $next, $content ];
    $next = $self->[TOK]->get;
  }
  my $else;
  my $else_content;
  my $end;
  if ($next->[TOKEN_TYPE] eq 'ext_else') {
    $else = $next;
    $else_content = $self->_parse_content;
    $next = $self->[TOK]->get;
  }
  else {
    $else = $else_content = $self->_empty($next);
  }
  if ($next->[TOKEN_TYPE] eq 'end') {
    if ($next->[TOKEN_END_TYPE] ne "" && $next->[TOKEN_END_TYPE] ne 'if') {
      push @errors, $self->_error($next, "Expected '.end' or '.end if' for .if started $if->[TOKEN_FILENAME]:$if->[TOKEN_LINE] but found '.end $next->[TOKEN_END_TYPE]'");
    }
    $end = $next;
  }
  else {
    $self->[TOK]->unget($next);
    $end = $self->_empty($next);
  }

  my $parser = Squirrel::Template::Expr::Parser->new;
  for my $cond (@conds) {
    local $SIG{__DIE__};
    unless (eval { $cond->[2] = $parser->parse($cond->[0][TOKEN_EXT_EXPR]); 1 }) {
      $cond->[2] = [ const => "", "" ];
      push @errors, $self->_error($cond->[0], ref $@ ? $@->[1] : $@);
    }
  }

  @{$if}[NODE_EXTIF_CONDS, NODE_EXTIF_ELSE, NODE_EXTIF_END] =
    ( \@conds, [ $else, $else_content ], $end );

  return @errors ? $self->_comp($if, @errors) : $if;
}

sub _parse_ext_while {
  my ($self, $while) = @_;

  my @errors;
  my $content = $self->_parse_content;
  my $end = $self->[TOK]->get;
  if ($end->[TOKEN_TYPE] eq 'end') {
    if ($end->[TOKEN_END_TYPE] ne "" && $end->[TOKEN_END_TYPE] ne 'while') {
      push @errors, $self->_error($end, "Expected '.end' or '.end while' for .while started $while->[TOKEN_FILENAME]:$while->[TOKEN_LINE] but found '.end $end->[TOKEN_END_TYPE]'");
    }
  }
  else {
    push @errors, $self->_error($end, "Expected '.end' for .while started $while->[TOKEN_FILENAME]:$while->[TOKEN_LINE] but found $end->[TOKEN_TYPE]");
    $self->[TOK]->unget($end);
    $end = $self->_empty($end);
  }

  my $parser = Squirrel::Template::Expr::Parser->new;
  my $cond_expr;
  local $SIG{__DIE__};
  unless (eval { $cond_expr = $parser->parse($while->[TOKEN_EXT_EXPR]); 1 }) {
    return $self->_error($while, "Could not parse condition for .while: " . ref $@ ? $@->[0] : $@);
  }

  @{$while}[NODE_TYPE, NODE_WHILE_COND, NODE_WHILE_CONTENT, NODE_WHILE_END] =
    ( "while", $cond_expr, $content, $end );

  return @errors ? $self->_comp($while, @errors) : $while;
}

sub _parse_iterateover {
  my ($self, $token) = @_;

  my $content = $self->_parse_content;
  my $end = $self->[TOK]->get;
  my $error;
  if ($end->[TOKEN_TYPE] eq 'end') {
    if ($end->[TOKEN_END_TYPE] && $end->[TOKEN_END_TYPE] ne 'iterateover') {
      $error = $self->_error($end, "Expected '.end' or '.end iterateover' for .iterateover started $token->[TOKEN_FILENAME]:$token->[TOKEN_LINE] but found '.end $end->[TOKEN_END_TYPE]'");
    }
  }
  else {
    $self->[TOK]->unget($end);
    $error = $self->_error($end, "Expected '.end' for .iterateover started $token->[TOKEN_FILENAME]:$token->[TOKEN_LINE] but found $end->[TOKEN_TYPE]");
    $end = $self->_empty($end);
  }

  my @exprs;
  {
    my $error;
    @exprs = $self->_parse_expr_list($token, $token->[TOKEN_ITERATEOVER_EXPR], \$error)
      or return $error;
  }

  my $callto = shift @exprs;
  @{$token}[NODE_ITERATEOVER_CALL, NODE_ITERATEOVER_CONTENT, NODE_ITERATEOVER_ARGS] = ( $callto, $content, \@exprs );

  return $error ? $self->_comp($token, $error) : $token;
}

sub _parse_expr_list {
  my ($self, $token, $text, $rerror) = @_;

  my $tokens = Squirrel::Template::Expr::Tokenizer->new($text);
  my $parser = Squirrel::Template::Expr::Parser->new;
  my @result;
  my $expr;
  local $SIG{__DIE__};
  unless (eval { $expr = $parser->parse_tokens($tokens); 1 }) {
    $$rerror = $self->_error($token, "Could not parse expression list: ".$@->[1]);
    return;
  }
  push @result, $expr;
  my $next = $tokens->get;
  while ($next->[0] eq 'op,') {
    unless (eval { $expr = $parser->parse_tokens($tokens); 1 }) {
      $$rerror = $self->_error($token, "Could not parse expression list: ".$@->[1]);
      return;
    }
    push @result, $expr;
    $next = $tokens->get;
  }
  if ($next->[0] ne 'eof') {
    $$rerror = $self->_error($token, "Expected , or end of expression list but found $next->[0]");
    return;
  }

  return @result;
}

sub _parse_error {
  my ($self, $error) = @_;

  push @{$self->[ERRORS]}, $error;

  return $error;
}

sub _parse_comment {
  my ($self, $comment) = @_;

  return;
}

sub errors {
  my ($self) = @_;

  return @{$self->[ERRORS]};
}

1;

=head1 NAME

Squirrel::Template::Parser - parse a stream of tokens from a template

=head1 SYNOPSIS

  use Squirrel::Template;
  my $t = Squirrel::Template::Tokenizer->new($text, $filename, $templater);
  my $p = Squirrel::Template::Parser->new($t, $templater);

  my $parse_tree = $p->parse;

  my @errors = $p->errors;

=head1 DESCRIPTION

Process the stream of tokens from a L<Squirrel::Template::Tokenizer>
object into a parse tree.

=head1 METHODS

=over

=item new($tokenizer, $templater)

Create a new parser.

=item parse()

Parse the stream of tokens and return a parse tree.

=item errors()

Returns any errors encountered parsing the tree as error tokens.

=back

=cut

