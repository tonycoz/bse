package Squirrel::Template::Constants;
use strict;
use Exporter qw(import);

our $VERSION = "1.001";

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

our %EXPORT_TAGS =
  (
   token => [ @token_base, @token_generic, @token_error ],
   node =>
   [
    @node_base, @node_iter, @node_cond, @node_comp, @node_with,
    @node_wrap, @node_switch, @node_error
   ],
  );

our @EXPORT_OK = ( map @$_, values %EXPORT_TAGS );

1;
