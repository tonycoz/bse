package Squirrel::Template::Tokenizer;
use strict;
use Squirrel::Template::Constants qw(:token);

our $VERSION = "1.010";

use constant QUEUE => 0;
use constant TEXT => 1;
use constant LINE => 2;
use constant NAME => 3;
use constant TMPLT => 4;
use constant INCLUDES => 5;

use constant TRACE => 0;

sub new {
  my ($class, $text, $name, $templater) = @_;

  return bless [ [], $text, 1, $name, $templater, [] ], $class;
}

my $tag_head = qr/(?:\s+<:-|<:-?)/;
my $tag_tail = qr/(?:-:>\s*|:>)/;

# simple to tokenize directives
my @simple = qw(endwrap switch endswitch eif or);

my $simple_re = join('|', @simple);

# starting keywords that are reserved (we catch them when used correctly)
my @reserved = qw(if iterator with wrap include);
push @reserved, @simple;

my $reserved_re = join('|', @reserved);

sub get {
  my ($self) = @_;

  my ($name, $line, $queue) = @{$self}[NAME, LINE, QUEUE];

  if (@$queue) {
    print STDERR "GET: @{$queue->[0]}[0,2,3] (queued) (", join(":", (caller)[0, 2]), ")\n" if TRACE;
    return shift @$queue;
  }
  unless (length $self->[TEXT]) {
    print STDERR "GET: none (", join(":", (caller)[0, 2]), ")\n" if TRACE;
    return;
  }

  if ($self->[TEXT] =~ s/\A(.*?)(($tag_head)\s*)//s) {
    my ($content, $tag_start, $head) = ($1, $2, $3);

    if (length $content) {
      push @$queue, [ "content", $content, $line, $name ];
      $self->[LINE] += $content =~ tr/\n//;
      $line = $self->[LINE];
    }

    if ($self->[TEXT] =~ s/\A((.*?)\s*($tag_tail))//s) {
      my ($tag_end, $body, $tail) = ($1, $2, $3);
      my $tag = $tag_start . $tag_end;

      $self->[LINE] += $tag =~ tr/\n//;
      if ($body =~ /\A($simple_re)(?:\s+(\S.*))?\z/s) {
	push @$queue, [ $1 => $tag, $line, $name, defined $2 ? $2 : '' ];
      }
      elsif ($body =~ m!\Ainclude\s+([\w/.-]+)(?:\s+([\w,]+))?\z!) {
	if (@{$self->[INCLUDES]} <= 10) {
	  my ($newtext, $filename, $error) = $self->[TMPLT]->include($1, $2);
	  if ($error) {
	    push @$queue, [ error => $tag, $line, $name, $newtext ];
	  }
	  else {
	    if (length $newtext) {
	      push @{$self->[INCLUDES]}, [ @{$self}[TEXT, NAME, LINE] ];
	      @{$self}[TEXT, NAME, LINE] = ( $newtext, $filename, 1 );
	    }
	    return $self->get if !@$queue && length $self->[TEXT];
	  }
	}
	else {
	  push @$queue, [ error => $tag, $line, $name, 'Too many levels of includes' ];
	}
      }
      elsif ($body =~ /\A=\s+(\S.*?)(?:\s+\|\s*(\w*))?\z/s) {
	push @$queue, [ expr => $tag, $line, $name, $1, $2 || "" ];
      }
      elsif ($body =~ /\A%\s+(\S.*?)(?:\s+\|\s*(\w+))?\z/s) {
	push @$queue, [ stmt => $tag, $line, $name, $1, $2 || "" ];
      }
      elsif ($body =~ /\A\.set\s+([a-zA-Z_][a-zA-Z0-9_]*(?:\.[a-zA-Z_][a-zA-Z0-9_]*)*)\s*=\s*(\S.*)\z/s) {
	push @$queue, [ set => $tag, $line, $name, $1, $2 ];
      }
      elsif ($body =~ /\A\.(while|if|elsif|switch)\s+(\S.*)\z/s) {
	push @$queue, [ "ext_$1" => $tag, $line, $name, $2 ];
      }
      elsif ($body =~ /\A\.else\z/s) {
	push @$queue, [ "ext_else" => $tag, $line, $name ];
      }
      elsif ($body =~ /\A\.for\s+([a-zA-Z_][a-zA-Z0-9_]*)\s+in\s+(\S.*)\z/s) {
	push @$queue, [ for => $tag, $line, $name, $1, $2 ];
      }
      elsif ($body =~ /\A\.define\s+(\S.*)\z/s) {
	push @$queue, [ define => $tag, $line, $name, $1 ];
      }
      elsif ($body =~ /\A\.end(?:\s+(\w+))?\z/) {
	push @$queue, [ end => $tag, $line, $name, defined $1 ? $1 : "" ];
      }
      elsif ($body =~ /\A\.call\s+(\S.*)?\z/) {
	push @$queue, [ call => $tag, $line, $name, $1 ];
      }
      elsif ($body =~ /\Aiterator\s+begin\s+(\w+)\s*(?:\s+(\S.*))?\z/s) {
	push @$queue, [ itbegin => $tag, $line, $name, $1, defined $2 ? $2 : '' ];
      }
      elsif ($body =~ /\Aiterator\s+separator(?:\s+(\w+))\z/) {
	push @$queue, [ itsep => $tag, $line, $name, $1 ];
      }
      elsif ($body =~ /\Aiterator\s+end(?:\s+(\w+))\z/) {
	push @$queue, [ itend => $tag, $line, $name, $1 ];
      }
      elsif ($body =~ /\Awith\s+begin\s+(\w+)\s*(?:\s+(\S.*))?\z/s) {
	push @$queue, [ withbegin => $tag, $line, $name, $1, defined $2 ? $2 : '' ];
      }
      elsif ($body =~ s/\Awith\s+end(?:\s+(\w+))?\z//) {
	push @$queue, [ withend => $tag, $line, $name, $1 ];
      }
      elsif ($body =~ /\Aif\s*([A-Z]\w+)(?:\s+(\S.*))?\z/s) {
	push @$queue, [ if => $tag, $line, $name, $1, defined $2 ? $2 : '' ];
      }
      elsif ($body =~ /\Aif\s*!([A-Z]\w+)(?:\s+(\S.*))?\z/s) {
	push @$queue, [ ifnot => $tag, $line, $name, $1, defined $2 ? $2 : '' ];
      }
      elsif ($body =~ /\Acase\s+(\w+)(?:\s+(\S.*))?\z/) {
	push @$queue, [ case => $tag, $line, $name, $1, defined $2 ? $2 : '' ];
      }
      elsif ($body =~ /\Acase\s+!(\w+)(?:\s+(\S.*))?\z/) {
	push @$queue, [ casenot => $tag, $line, $name, $1, defined $2 ? $2 : '' ];
      }
      elsif ($body =~ /\Awrap\s+here\z/) {
	push @$queue, [ wraphere => $tag, $line, $name ];
      }
      elsif ($body =~ m!\Awrap\s+([\w/.-]+)(?:\s+(\S.*))?\z!s) {
	push @$queue, [ wrap => $tag, $line, $name, $1, defined $2 ? $2 : '' ];
      }
      elsif ($body =~ /\A($reserved_re)\b/) {
	push @$queue, [ error => $tag, $line, $name, "Syntax error: incorrect use of '$1'" ];
      }
      elsif ($body =~ /\A(\w+)(?:\s+(\S.*))?\z/s) {
	push @$queue, [ tag => $tag, $line, $name, $1, defined $2 ? $2 : '' ];
      }
      elsif ($body =~ /\A\#\s*(.*)\z/s) {
	push @$queue, [ comment => $tag, $line, $name, $1 ];
      }
      else {
	my $start = length $body > 20 ? substr($body, 0, 17) . "..." : $body;
	push @$queue, [ error => $tag, $line, $name, "Syntax error: unknown tag start '$start'" ];
      }
    }
    else {
      my ($name_maybe) = $self->[TEXT] =~ /\A([.=]?\w+)/;
      my $tag = $tag_start . $self->[TEXT];
      $self->[TEXT] = "";
      my $tag_name = $name_maybe || "(no name found)";
      push @$queue, [ error => $tag, $self->[LINE], $name, "Unclosed tag '$tag_name'" ];
      $self->[LINE] += $tag =~ tr/\n//;
    }
  }
  else {
    my $text = $self->[TEXT];
    $self->[TEXT] = '';
    my $line = $self->[LINE];
    $self->[LINE] += $text =~ tr/\n//;
    push @$queue, [ "content", $text, $line, $name ];
  }

  while ($self->[TEXT] eq '' && @{$self->[INCLUDES]}) {
    @{$self}[TEXT, NAME, LINE] = @{pop @{$self->[INCLUDES]}};
  }
  if ($self->[TEXT] eq '') {
    push @$queue, [ eof => '', $self->[LINE], $self->[NAME] ];
  }

  #use Devel::Peek;
  #Dump($self->[TEXT]);

  print STDERR "GET: @{$queue->[0]}[0,2,3] (", join(":", (caller)[0, 2]), ")\n" if TRACE;

  return shift @$queue;
}

sub unget {
  my ($self, $token) = @_;

  print STDERR "UNGET: @{$token}[0,2,3] (", join(":", (caller)[0, 2]), ")\n" if TRACE;

  unshift @{$self->[QUEUE]}, $token;
}

sub peek {
  my ($self) = @_;

  if (@{$self->[QUEUE]}) {
    print STDERR "PEEK: @{$self->[QUEUE][0]}0,2,3] (queued) (", join(":", (caller)[0, 2]), ")\n" if TRACE;
    return $self->[QUEUE][0];
  }
  else {
    if ($self->[TEXT] eq '') {
      print STDERR "PEEK: none (", join(":", (caller)[0, 2]), ")\n" if TRACE;
      return;
    }
    my $result = $self->get;
    unshift @{$self->[QUEUE]}, $result;

    print STDERR "PEEK: @{$result}[0,2,3] (", join(":", (caller)[0, 2]), ")\n" if TRACE;

    return $result;
  }
}

sub peek_type {
  my ($self) = @_;

  my $token = $self->peek
    or return '';
  return $token->[0];
}

1;

=head1 NAME

Squirrel::Template::Tokenizer - generate a stream of tokens from a template

=head1 SYNOPSIS

  use Squirrel::Template::Constants qw(:token);
  my $t = Squirrel::Template::Tokenizer->new($text, $filename, $templater);

  my $token = $t->get;
  $t->unget($token);
  my $next_token = $t->peek;
  my $next_type = $t->peek_type;

  my $type = $token->[TOKEN_TYPE];
  my $original = $token->[TOKEN_ORIG];
  my $line = $token->[TOKEN_LINE];
  my $filename = $token->[TOKE_FILENAME];

=head1 DESCRIPTION

Incrementally returns a stream of tokens from the supplied text,
processing any include directives.

Each token is returned as an array reference, where the first four members are:

=over

=item *

token type - a simple identifier for the token, such as C<tag> or C<content>.

=item *

original text - the original text representing that token in the
source text.  For a C<content> token this is the actualy content.

=item *

line number - the starting line number of the token.  A token may
continue over several lines and for a non-content token with a
white-space eating leader it may not be obvious that the token starts
on this line.

=item *

file name - the name of the file this token was read from.  For the
original text this will be the C<$filename> supplied to the
constructor, but it will change for included files.

=back

=head1 METHODS

=over

=item new($text, $filename, $templater)

Create a new tokenizer.  C<$text> is the text to parse.  C<$filename>
is the source file of the text. C<$templater> is a
L<Squirrel::Template> object.

=item get()

Returns the next token from the stream, consuming it.  The token
stream is always terminated by an C<eof> token.  Returns nothing once
the C<eof> token has been returned.

=item unget($token)

Adds C<$token> to the front of the queue of tokens to be retrieved.

=item peek()

Retrieve the next token from the stream without consuming it.

=item peek_type()

Returns the type of the next token.  If there is no token returns an
empty string.

=back

=head1 AUTHOR

Tony Cook <tony@develop-help.com>

=cut

