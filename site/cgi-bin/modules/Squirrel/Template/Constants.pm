package Squirrel::Template::Constants;
use strict;
use Exporter qw(import);

our $VERSION = "1.004";

sub _define_sequence {
  my ($keys, $start) = @_;

  $start ||= 0;

  require constant;
  for my $key (@$keys) {
    constant->import($key => $start++);
  }
}

my @token_base = qw(TOKEN_TYPE TOKEN_ORIG TOKEN_LINE TOKEN_FILENAME);
_define_sequence(\@token_base, 0);
my @token_generic = qw(TOKEN_TAG_NAME TOKEN_TAG_ARGS);
_define_sequence(\@token_generic, 4);
my @token_error = qw(TOKEN_ERROR_MESSAGE);
_define_sequence(\@token_error, 4);
my @token_expr = qw(TOKEN_EXPR_EXPR);
_define_sequence(\@token_expr, 4);
my @token_set = qw(TOKEN_SET_VAR TOKEN_SET_EXPR);
_define_sequence(\@token_set, 4);
my @token_end = qw(TOKEN_END_TYPE);
_define_sequence(\@token_end, 4);
my @token_for = qw(TOKEN_FOR_NAME TOKEN_FOR_EXPR);
_define_sequence(\@token_for, 4);

my @node_base = qw(NODE_TYPE NODE_ORIG NODE_LINE NODE_FILENAME NODE_TAG_NAME NODE_TAG_ARGS);
_define_sequence(\@node_base, 0);
my @node_iter = qw(NODE_ITERATOR_LOOP NODE_ITERATOR_SEPARATOR NODE_ITERATOR_SEPTOK NODE_ITERATOR_ENDTOK);
_define_sequence(\@node_iter, 6);
my @node_cond = qw(NODE_COND_TRUE NODE_COND_FALSE NODE_COND_OR NODE_COND_EIF);
_define_sequence(\@node_cond, 6);
my @node_comp = qw(NODE_COMP_FIRST);
_define_sequence(\@node_comp, 4);
my @node_with = qw(NODE_WITH_CONTENT NODE_WITH_END);
_define_sequence(\@node_with, 6);
my @node_wrap = qw(NODE_WRAP_FILENAME NODE_WRAP_ARGS NODE_WRAP_CONTENT);
_define_sequence(\@node_wrap, 4);
my @node_switch = qw(NODE_SWITCH_CASES NODE_SWITCH_END);
_define_sequence(\@node_switch, 5);
my @node_error = qw(NODE_ERROR_MESSAGE);
_define_sequence(\@node_error, 4);
my @node_expr = qw(NODE_EXPR_EXPR NODE_EXPR_FORMAT);
_define_sequence(\@node_expr, 4);
my @node_set = qw(NODE_SET_VAR NODE_SET_EXPR);
_define_sequence(\@node_set, 4);
my @node_define = qw(NODE_DEFINE_NAME NODE_DEFINE_END NODE_DEFINE_CONTENT);
_define_sequence(\@node_define, 4);
my @node_call = qw(NODE_CALL_NAME NODE_CALL_LIST);
_define_sequence(\@node_call, 4);
my @node_for = qw(NODE_FOR_NAME NODE_FOR_EXPR NODE_FOR_END NODE_FOR_CONTENT);
_define_sequence(\@node_for, 4);

our %EXPORT_TAGS =
  (
   token => [ @token_base, @token_generic, @token_error, @token_expr,
	      @token_set, @token_end, @token_for ],
   node =>
   [
    @node_base, @node_iter, @node_cond, @node_comp, @node_with,
    @node_wrap, @node_switch, @node_error, @node_expr, @node_set,
    @node_define, @node_call, @node_for
   ],
  );

our @EXPORT_OK = ( map @$_, values %EXPORT_TAGS );

1;
