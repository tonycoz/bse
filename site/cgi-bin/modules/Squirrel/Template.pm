package Squirrel::Template;
use vars qw($VERSION);
use strict;
use Squirrel::Template::Tokenizer;
use Squirrel::Template::Parser;
use Squirrel::Template::Deparser;
use Squirrel::Template::Processor;
use Squirrel::Template::Expr;
use Squirrel::Template::Params;

use constant MAX_SCOPES => 50;

use Carp qw/cluck confess/;
BEGIN {
  unless ( defined &DEBUG ) {
    require constant;
    constant->import(DEBUG => 0);
  }
}

use constant DEBUG_GET_PARMS => 0;

our $VERSION = "1.031";

my %compile_cache;

my $tag_head = qr/(?:\s+<:-|<:-?)/;
my $tag_tail = qr/(?:-:>\s*|:>)/;

sub new {
  my ($class, %opts) = @_;

  $opts{errout} = \*STDERR;
  $opts{param} = [];
  $opts{wraps} = [];
  $opts{errors} = [];
  $opts{def_format} ||= "";
  $opts{delimiters} ||=
    [
     [ "<:", ":>" ],
    ];

  return bless \%opts, $class;
}

sub _slurp {
  my ($self, $filename, $error) = @_;

  my $opened = open my $fh, "<", $filename;
  unless ($opened) {
    $$error = "Cannot open $filename: $!";
    return;
  }
  if ($self->{utf8}) {
    my $charset = $self->{charset} || "utf-8";
    binmode $fh, ":encoding($charset)";
  }
  my $data = do { local $/; <$fh> };
  close $fh;

  return $data;
}

sub low_perform {
  my ($self, $acts, $func, $args, $orig) = @_;

  $args = '' unless defined $args;
  $orig = '' unless defined $orig;

  DEBUG and print STDERR ">low_perform(..., $func, '$args', '$orig')\n";

  my $fmt;
  if ($acts->{_format} && $args =~ s/\|(\S+)$//) {
    $fmt = $1;
    DEBUG and print STDERR "Format <$fmt>\n";
  }

  if (exists $acts->{$func}) {
    $args =~ s/^\s+//;
    $args =~ s/\s+$//;
    my $value;
    my $action = $acts->{$func};
    if (ref $action) {
      if (ref $action eq 'CODE') {
	$value = $action->($args, $acts, $func, $self);
      }
      elsif (ref $action eq 'ARRAY') {
	my ($code, @params) = @$action;
	if (ref $code) {
	  $value = $code->(@params, $args, $acts, $func, $self);
	}
	else {
	  # assume it's a method name, first param is the object/class
	  my $obj = shift @params;
	  $value = $obj->$code(@params, $args, $acts, $func, $self);
	}
      }
      elsif (ref $action eq 'SCALAR') {
	$value = $$action;
      }
      else {
	return $orig;
      }
    }
    else {
      $value = $action;
    }
    return unless defined $value;
    return $fmt ? $acts->{_format}->($value, $fmt) : $value;
  }
  if ($func eq 'summary') {
    my $size = 80;
    my $temp = $args;
    $temp =~ s/^\s+|\s+$//g;
    $size = $1 if $temp =~ s/^(\d+)\s+//;
    my ($newfunc, $newargs) = split /\s+/, $temp, 2;
    $newargs = '' if !defined $newargs;
    if (exists $acts->{$newfunc}
       and defined(my $value = $self->perform($acts, $newfunc, $newargs))) {
      # work out a summary
      return $value if length($value) < $size;
      $value = substr($value, 0, $size);
      $value =~ s/\s+\S*$/.../;
      return $value;
    }
    # otherwise fall through
  }
  elsif ($func eq "param") {
    return $self->tag_param($args);
  }

  return $self->{verbose} ? "** unknown function $func **" : $orig;
}

sub perform {
  my ($self, $acts, $func, $args, $orig) = @_;

  $args = '' unless defined $args;
  
  print STDERR "  > perform $func $args\n" if DEBUG > 1;

  my $value;
  eval {
    $value = $self->low_perform($acts, $func, $args, $orig);
  };

  if ($@) {
    my $msg = $@;
    $msg =~ /\bENOIMPL\b/
      and return $orig;
    print STDERR "Eval error in perform: $msg\n";
    $msg =~ s/([<>&])/"&#".ord($1).";"/ge;
    return "<!-- ** $msg ** -->";
  }

  unless (defined $value) {
    cluck "** undefined value returned by $func $args **";
    $value = '';
  }

  print STDERR "  < perform\n" if DEBUG > 1;

  return $value;
}

# display a trace message for ENOIMPL, if enabled
sub trace_noimpl {
  my $self = shift;

  $self->{trace_noimpl} or return;
  my $err = $self->{errout};
  print $err @_;
}

sub find_template {
  my ($self, $name) = @_;

  return unless $self->{template_dir};

  my @dirs = ref $self->{template_dir} ? @{$self->{template_dir}} : $self->{template_dir};
  for my $dir (@dirs) {
    if (-e "$dir/$name") {
      return "$dir/$name";
    }
  }

  return;
}

sub include {
  my ($self, $name, $options) = @_;

  defined $options or $options = '';
  
  print STDERR "Including $name\n" if DEBUG;

  my $filename = $self->find_template($name);
  unless ($filename) {
    return wantarray ? ('', '' ) : '' if $options eq 'optional';

    print STDERR "** Could not find include code $name\n";
    my $error = "cannot find include $name in path";
    return wantarray ? ( $error, undef, 1 ) : "* $error *";
  }

  print STDERR "Found $filename\n" if DEBUG;

  my $error;
  my $data = $self->_slurp($filename, \$error)
    or return wantarray ? ( $error, $filename, 1 ) : "* $error *";
  print STDERR "Included $filename >>$data<<\n"
      if DEBUG;

  $data = "<!-- included $filename -->$data<!-- endinclude $filename -->"
      if DEBUG;

  return wantarray ? ($data, $filename) : $data;
}

sub tag_param {
  my ($self, $arg) = @_;

  for my $param (@{$self->{param}}) {
    if (exists $param->{$arg}) {
      return $param->{$arg};
    }
  }

  return "";
}

my $parms_re = qr/\s*\[\s*(\w+)
	                (
	                 (?:\s+
			  (?:
			   [^\s\[\]]+
                           |
			   \"[^"]*\"
			   |
			   \[[^\]\[]+?\]
                           |
                           \[(?:[^\]\[]*\[[^\]\[]*\])+[^\]\[]*\]
			  )
			 )*
                        )
	            \s*\]\s*/x;

sub parms_re {
  return $parms_re;
}

sub format {
  my ($self, $text, $format) = @_;

  unless ($self->{formats}{$format}) {
    push @{$self->{errors}}, "Unknown formatter '$format'";
    return "$text*Unknown formatter '$format'";
  }

  return $self->{formats}{$format}->($text);
}

# dummy
sub tag_summary {
}

sub get_parms {
  my ($templater, $args, $acts, $keep_unknown) = @_;

  my $orig = $args;

  print STDERR "** Entered get_parms -$args-\n" if DEBUG_GET_PARMS;
  my @out;
  defined $args or Carp::cluck("undefined \$args");
  while (length $args) {
    if ($args =~ s/^$parms_re//x) {
      my ($func, $subargs) = ($1, $2);
      $subargs = '' unless defined $subargs;
      if (exists $acts->{$func}) {
	print STDERR "  Evaluating [$func $subargs]\n" if DEBUG_GET_PARMS;
	my $value = $templater->perform($acts, $func, $subargs);
	defined $value or die "ENOIMPL";
	print STDERR "    Result '$value'\n" if DEBUG_GET_PARMS;
	push(@out, $value);
      }
      else {
	print STDERR "  Unknown function '$func' for '$orig'\n" 
	  if DEBUG_GET_PARMS;
	if (DEBUG_GET_PARMS) {
	  print STDERR "  Available functions: ", join(",", sort keys %$acts),"\n";
	  
	}
	if ($keep_unknown) {
	  push @out, [ $func, $subargs ];
	}
	else {
	  die "ENOIMPL '$func $subargs' in '$orig'\n";
	}
      }
    }
    elsif ($args =~ s/^\s*\"((?:[^\"\\]|\\[\\\"]|\\)*)\"\s*//) {
      my $out = $1;
      $out =~ s/\\([\\\"])/$1/g;
      print STDERR "  Adding quoted string '$out'\n" if DEBUG_GET_PARMS;
      push(@out, $out);
    }
    elsif ($args =~ s/^\s*(\S+)\s*//) {
      print STDERR "  Adding unquoted string '$1'\n" if DEBUG_GET_PARMS;
      push(@out, $1);
    }
    else {
      print STDERR "  Left over text '$args'\n" if DEBUG_GET_PARMS;
      last;
    }
  }
  print STDERR "  Result (",join("|", @out),")\n" if DEBUG_GET_PARMS;

  @out;
}

sub errors {
  my ($self) = @_;

  return @{$self->{errors}};
}

sub clear_errors {
  my ($self) = @_;

  $self->{errors} = [];
}

sub start_wrap {
  my ($self, $args) = @_;

  if (@{$self->{param}} >= 10) {
    return;
  }

  unshift @{$self->{param}}, $args;

  return 1;
}

sub end_wrap {
  my ($self) = @_;

  shift @{$self->{param}};

  return 11;
}

sub start_scope {
  my ($self, $context, $vars) = @_;

  if (@{$self->{scopes}} >= MAX_SCOPES) {
    die "Too many scope levels\n";
  }

  push @{$self->{scopes}}, $vars || {};
  push @{$self->{scope_contexts}}, $context;
}

sub end_scope {
  my ($self) = @_;

  pop @{$self->{scopes}};
}

sub backtrace {
  my ($self) = @_;

  return @{$self->{scope_contexts}};
}

sub top_scope {
  my ($self) = @_;

  return $self->{scopes}[-1];
}

sub get_var {
  my ($self, $name) = @_;

  for my $scope (reverse @{$self->{scopes}}) {
    if (exists $scope->{$name}) {
      return $scope->{$name};
    }
  }

  $self->{error_not_defined}
    and die "Variable '$name' not set\n";

  die "ENOIMPL\nVariable '$name' not set";
}

sub set_var {
  my ($self, $name, $value) = @_;

  $self->{scopes}[-1]{$name} = $value;
}

sub define_macro {
  my ($self, $name, $content, $defaults) = @_;

  $self->{defines}{$name} = [ $content, $defaults ];

  return 1;
}

sub get_macro {
  my ($self, $name) = @_;

  my $define = $self->{defines}{$name}
    or return;

  return @$define;
}

sub parse {
  my ($self, $template, $name) = @_;

  my $t = Squirrel::Template::Tokenizer->new($template, $name || "<string>",
					     $self, $self->{delimiters});
  my $p = Squirrel::Template::Parser->new($t, $self);

  my $node = $p->parse;

  push @{$self->{errors}}, $p->errors;

  return $node;
}

sub parse_filename {
  my ($self, $filename) = @_;

  my $key = "Squirrel::Template::file:$filename";
  my ($date, $size);

  if ($self->{cache_locally}) {
    ($date, $size) = (stat $filename)[9, 7]
      unless $date;

    my $cached = $compile_cache{$filename};
    if ($cached) {
      if ($cached->[0] == $date && $cached->[1] == $size) {
	#print STDERR "Found cached $filename / $date / $size\n";
	return $cached->[2];
      }
      else {
	#print STDERR "Cached but old $filename / $date / $size\n";
	delete $compile_cache{$filename};
      }
    }
  }

  if ($self->{cache}) {
    ($date, $size) = (stat $filename)[9, 7]
      unless $date;

    my $cached = $self->{cache}->get($key);
    if ($cached) {
      if ($cached->[0] == $date && $cached->[1] == $size) {
	#print STDERR "Found cached $key / $date / $size\n";
	return $cached->[2];
      }
      else {
	#print STDERR "Cached but old $key / $date / $size\n";
	$self->{cache}->delete($key);
      }
    }
  }

  my $message;
  my $text;

  if (($text, $message) = $self->_slurp($filename)) {
    unless ($message) {
      my $parsed;

      ($parsed, $message) = $self->parse($text, $filename);

      if ($parsed && $self->{cache}) {
	#print STDERR "Set $key / $date / $size\n";
	$self->{cache}->set($key => [ $date, $size, $parsed ]);
      }

      if ($parsed && $self->{cache_locally}) {
	$compile_cache{$filename} = [ $date, $size, $parsed ];
      }

      return ($parsed, $message);
    }
  }

  return (undef, $message);
}

sub parse_file {
  my ($self, $name) = @_;

  my $message;
  my $filename = $self->find_template($name);
  if ($filename) {
    return $self->parse_filename($filename);
  }
  else {
    $message = "File $name not found";
  }

  return (undef, $message);
}

sub replace {
  my ($self, $parsed, $acts, $vars) = @_;

  local $self->{errors} = [];

  local $self->{scopes} = [];
  push @{$self->{scopes}}, $vars if $vars;
  my $my_scope = 
    {
     globals => {},
     params => Squirrel::Template::Params->new(undef, $self, undef),
    };
  push @{$self->{scopes}}, $my_scope;
  local $self->{scope_contexts} = [];

  local $self->{defines} = {};

  my $oldparam_tag = $acts->{param};
  local $acts->{param} = $oldparam_tag || [ tag_param => $self ];

  my $processor = Squirrel::Template::Processor->new($acts, $self);

  if ($self->{preload}) {
    my ($parsed, $error) = $self->parse_file($self->{preload});
    if ($parsed) {
      # process and discard, just for definitions, initializations
      $processor->process($parsed);
    }
    elsif ($error) {
      push @{$self->{errors}}, [ error => "", 0, $self->{preload}, $error ];
    }
  }

  return wantarray
    ? $processor->process($parsed)
      : join("", $processor->process($parsed));
}

sub replace_template {
  my ($self, $template, $acts, $iter, $name, $vars) = @_;

  my $parsed = $self->parse($template, $name);

  return scalar $self->replace($parsed, $acts, $vars);
}

sub show_page {
  my ($self, $base, $page, $acts, $iter, $alt, $vars) = @_;

  print STDERR ">> show_page\n" if DEBUG;
  print STDERR "  page $page\n" if DEBUG && $page;
  print STDERR "  base $base\n" if DEBUG && $base;

  $acts ||= {};

  my $file;
  if ($base) {
    $file = $page ? "$base/$page" : $base;
  }
  else {
    $file = $self->find_template($page);
    if (!$file and $alt) {
      $file = $self->find_template($alt);
    }
    $file
      or die "Cannot find template $page";
  }

  my ($parsed, $error) = $self->parse_filename($file);

  $error
    and die $error;

  my $result = scalar $self->replace($parsed, $acts, $vars);

  print STDERR "<< show_page\n" if DEBUG;

  return $result;
}


__END__

=head1 NAME

  Squirrel::Template - simple templating system

=head1 SYNOPSIS

  use Squirrel::Template;
  my $templater = Squirrel::Template->new(template_dir => $some_dir);
  my $result = $templater->show_page($base, $filename, \%acts, undef, $alt);
  my $result = $templater->replace_template($text, \%acts, undef, $display_name);
  my @errors = $templater->errors;
  my @args = $templater->get_parms($args, \%acts, $keep_unknown)

=head1 DESCRIPTION

BSE's template engine.

=head1 METHODS

=over 4

=item new()

  $templater = Squirrel::Template->new(%opts);

Create a new templating object.

Possible options are:

=over 4

=item verbose

If a tag isn't found in the actions then it is replaced with an error
message rather than being left in place.

=item template_dir

Used to find wrapper and include templates.  This can be either a
scalar, or a reference to an array of locations to search for the
wrapper.

=item utf8

If this is true then the template engine works in unicode internally.
Template files are read into memory using the charecter set specified
by C<charset>.

=item charset

Ignored unless C<utf8> is true.  Specifies the character encoding used
by template files.  Defaults to C<"utf-8">.

=item cache

A BSE::Cache object to use for caching compiled templates.  Note that
templates are currently only cached by filename.

=item formats

A hashref of content formatters used for formatting C<< E<lt>=
... E<gt> >> tags.

=item def_format

The default format for C<< E<lt>= ... E<gt> >> tags.

=back

=item show_page()

  $text = $templ->show_page($base, $template, \%acts, $iter)

Performs template replacement on the text from the file $template in
directory $base.

=item replace_template()

  $text = $templ->replace_template($intext, \%acts, $iter, $name)

Performs template replacement on C<$intext> using the tags in
C<%acts>.  C<$iter> is accepted only for backward compatibility and it
no longer used.  Errors are reported as if C<$intext> had been read
from a file called C<$name>.

=item errors()

Return errors from the last show_page() or replace_template().

This can include:

=over

=item *

tokenization errors - an unknown token was found in the template

=item *

parsing errors - mismatched if/eif, etc

=item *

processing errors - die from tag handlers, etc

=item *

file errors - missing include or wrap files, and recursion from those.

=back

Returns a list of error tokens, each of which is an array reference
with:

=over

=item *

The text "error".

=item *

An template text that caused the error.  This may be blank some cases.

=item *

The line number.

=item *

The filename.  If you called replace_template() this will be the
C<$name> supplied to replace_template().

=item *

An error message.

=back

=item get_parms()

  my @args = get_parms($args, $acts, $keep_unknown)

Does simple and stupid processing of C<$args> parsing it for a list of
arguments.

Possible arguments that are parsed are:

=over

=item *

C<[> I<tagname> I<arguments> C<]> - return the results of calling the
specified tag.  Only a limited amount of nesting is parsed.

=item *

C<">I<text>C<"> - quoted text.  No escaping is done on the text.

=item *

I<text> - plain text not containing any C<[> or C<]>.

=back

Returns a list of parsed arguments.

If I<tagname> in C<$args> isn't defined, dies with an C<ENOIMPL\n>
message.

=back

=head1 TEMPLATE SYNTAX

This syntax provides mechanisms similar to those provided by Template
Toolkit or Mason, while retaining the older syntax below.

See L<Squirrel::Template::Expr> for information on expression syntax.

=over

=item *

C<< <:= I<expression> :> >>

C<< <:= I<expression> | I<format> :> >>

Replaced with the result of evaluating I<expression> and formatted by
the formatter specified by I<format>.

=item *

C<< <:% I<expression> ; ... :> >>

A list of expressions, evaluated in order.  The expression results are
discarded.

=item *

C<< <:.if I<expression> :>
I<content>
<:.elsif I<expression> :>
I<content>
<:.else :>
I<content>
<:.end:> >>

Evaluate each expression in turn and return the matching content.
C<.elsif> clauses can be repeated as desired.  The C<.else> clause is
optional.  The C<.end> token can be C<.end if>.

=item *

C<< <:.set I<variable> = I<expression> :> >>

Set the specified variable to the value of the expression.

=item *

C<< <:.for I<variable-name> in I<expression> :> I<content> <:.end:> >>

Loop over the contents of the specified list.

Also sets the C<loop> variable to a hash containing useful
information, see L</The loop variable> below.

If you're calling a perl method on an object directly, you will
typically want to surround the call with [] to process the call in
list content:

  <:.for i in [ article.children ]:>

The C<.end> token can also be C<.end for>.

=item *

C<< <:.define I<name> :> I<content> <:.end:> >>

=item *

C<< <:.define I<name>; name1:value1, name2:value2 :> I<content> <:.end:> >>

Define a macro called I<name> with the specified content.  The C<.end>
token can be C<.end define>.

eg.

  <:.define somename:>
  some content
  <:.end define:>

The second form provides defaults for calls to the macro.

=item *

C<< <:.call I<name-expression> :> >>

C<< <:.call I<name-expression>, I<variable-name-expression>:I<expression>, ...:> >>

Call the named macro, or if there is no such macro, the named template
file setting specified variables to the given values.

eg.

  <:# call foo, setting bar to "hello" :>
  <:.call "foo", "bar":"hello":>

While I<variable-name-expression> is currently an expression, it
should be limited to a quoted identifier.

Changes to any top level variables are scoped to inside the called
macro or file.

=item *

C<< <:.iterateover I<callback> :> I<content> <:.end :> >>

C<< <:.iterateover I<callback>, I<arguments>... :> I<content> <:.end :> >>

Calls back into the target supplied callback to set variables which
can then be replaced on each iteration.

=item *

C<< <:.while I<condition> :> I<content> <:.end :> >>

Produce I<content> while I<condition> is true.

=item *

C<< <:.wrap I<name>, I<name>:I<value> ... :> >>

Wrap content up until C<< <:.end wrap:> >> or end of file with the
content from the file or macro I<name>.

=back

=head1 Special Variables

=head2 The loop variable

Each C<.for> loop defines a C<loop> variable.  If you have nested
loops, you can define an alias to the variable, eg:

  <:.for i in outer:>
    <:.set outerloop = loop:>
    <:.for j in inner:>
      <:= outerloop.count :>
    <:.end:>
  <:.end:>

The following values are set in C<loop>

=over

=item *

first, last - the first and last values in the list.  These may be
undef if the list is empty.

=item *

size - the number of elements in the list

=item *

is_last, is_first - true if the current element is the last or first
element respectively.

=item *

count - the index of the current element, starting from 1.

=item *

index - the index of the current element, starting from 0.

=item *

parity - "odd" or "even".  The first element is "even".

=item *

odd, even - true if the parity is "odd" or "even", respectively.

=item *

prev, next - the previous or next element respectively, if any.

=item *

list - the list argument to C<.for>.

=item *

current - the current item in the iteration.

=back

=head2 params

This is set to the names and values supplied in a C<wrap> request, so:

  <:= params.name :>

is equivalent to:

  <: param name :>

=head2 globals

C<globals> provides a top-level hash to fill as required.  This can be
used to pass information from an inner-scope back to an outer scope.

=head1 OLD TEMPLATE SYNTAX

This is the older template syntax that is retained for compatibility.

In general, if the tag has no definition the original tag directive is
left in place.  If the tag has sub-components (like C<if> or
C<iterate>) tag replacement is done on the sub-components.

Template directives start with C<< <: >>, if a C<-> is found
immediately after the C<:> any whitespace before the tag is also
replaced.

Template directives end with C<< :> >>, if a C<-> if found immediately
before the C<:> any whitespace after the tag is also replaced.

eg.

  <: tag foo -:>  sample  <:-  tag bar :>

is treated the same as:

  <: tag foo :>sample<: tag bar :>

Directives available in templates:

=over

=item  *

C<< <: I<name> I<args> :> >>

Replaced with the value of the tag.  See L</Simple tag evaluation>.

=item *

C<< <: iterator begin I<name> I<args> :> I<text> <: iterator separator I<name> :> I<separator> <: iterator end I<name> :> >>

C<< <: iterator begin I<name> I<args> :> I<text> <: iterator end I<name> :> >>

Replaced with repeated templating of I<text> separated by I<separator>.

See L</Iterator tag evaluation>.

=item *

C<< <: ifI<Name> I<args> :> I<true> <: or :> I<false> <: eif :> >>

C<< <: ifI<Name> I<args> :> I<true> <: eif :> >>

C<< <: if I<Name> I<args> :> I<true> <: or I<Name> :> I<false> <: eif I<Name> :> >>

C<< <: if I<Name> I<args> :> I<true> <: eif I<Name> :> >>

Emits I<true> if the tag evaluates to a true value, otherwise the
I<false> text.  See L</Conditional tag evaluation>.

Note that only the C<if> now requires the C<Name>.  The C<or> and
C<eif> may include the name, but it is not required.  If the C<Name>
is supplied it must match the C<if> C<Name> or an error will be
returned.

=item *

C<< <: if!I<Name> I<args> :> I<false> <: eif :> >>

C<< <: if !I<Name> I<args> :> I<false> <: eif I<Name> :> >>

Emits I<false> if the tag evaluates to a false value.  See
L</Conditional tag evaluation>.

=item *

C<< <: with begin I<name> I<args> :> I<replaced> <: with end I<name> :> >>

Calls C<< $acts->{"with_I<name>"}->($args, $replaced, "", \%acts,
I<$name>, $templaer) >> where C<$replaced> is the processed text and
inserts that.

=item *

C<< <: # I<your comment> :> >>

A comment, not included in the output.

=item *

C<< <:switch:><:case I<Name> I<optional-args> :>I<content> ... <:endswitch:> >>

Replaced with the first matching conditional where C<< <:case I<Name>
I<optional-args> :> >> is treated like an C<if>.

A case may also be C<< <:case !I<Name> :> >>, in which the case
matches the same as an C<< if !I<Name> >>.

A C<< <:case default:> >> is always true.

=item *

C<< <: include I<filename> I<options> :> >>

Replaced with the content of the supplied filename.

If the file I<filename> is not found, this results in an error being
inserted (and reported via L</errors()>) unless I<options> contains
C<optional>.

No more than 10 levels of include can be nested.

=item *

C<< <: wrap I<templatename> :> I<wrapped> <:endwrap:> >>

C<< <: wrap I<templatename> I<name> => I<value>, ... :> I<wrapped> <:endwrap> >>

The C<< <:endwrap:> >> is optional.  A wrapper will be terminated by
end of file if not otherwise terminated.

Processes I<templatename> as a template.  Within that template C<< <:
wrap here :> >> will be replaced with I<wrapped>.

The values specified by the C<< I<name> => I<value> >> are used to
populate the value of the built-in param tag.

Wrapping can be nested up to 10 levels.

=item *

C<< <: wrap here :> >>

Returns the wrapped content within a wrapper template.  Returns an
error if not within a wrapper template.

=back

=head1 TAG EVALUATION

=head2 Simple tag evaluation

Tag definitions in C<%acts> can be in any of five forms:

=over

=item *

A simple scalar - the value of the scalar is returned.

=item *

A scalar reference - the referred to scalar is returned.

=item *

A code reference - the code reference is called as:

  $code->($args, \%acts, $tagname, $templater)

=item *

An array reference starting with a code reference, followed by
arguments, eg C<< [ \&tag_sometag, $foo, $bar ] >>.  This is called
as:

  $code->($foo, $bar, \%acts, $tagname, $templater)

=item *

An array reference starting with a scalar, followed by an object or
class name, followed by arguments, eg C<< [ method => $obj, $foo, $bar
] >>.  This is called as:

  $obj->$method($foo, $bar, \%acts, $tagname, $templater)

=back

A warning is produced if the tag returns an undef value.

=head2 Conditional tag evaluation

Given a C<< ifI<SomeName> >>, does L</Simple tag evaluation> on the
first tag of C<< ifI<SomeName> >> or C<< I<someName> >> found.

Unlike simple tag evaluation this does not warn if the result is undef.

=head2 Iterator tag evaluation

This uses two members of C<%acts>:

=over

=item *

C<< iterate_I<name>_reset >> - called to start iteration.  Optional
but recommended.

=item *

C<< iterate_I<name> >> - called until it returns false for each
iteration.

=back

Either can be any of:

=over

=item *

a code reference - called as:

  $code->($args, \%acts, $name, $templater)

=item *

an array reference starting with a code reference:

  $arrayref->[0]->(@{$arrayref}[1 .. $#$arrayref], \%acts, $name, $templater);

=item *

an array reference starting with a scalar:

  $arrayref->[1]->$method(@{$arrayref}[2 .. $#$arrayref], \%acts, $name, $templater);

=back

=head1 SPECIAL ACTIONS

So far there's just one:

=over 4

=item _format

If the _format action is defined in your $acts then if a function tag
has |text at the end of it then the function is evaluated, and the
resulting text and the text after the | is passed to the format
function.

=back

=head1 SEE ALSO

Squirrel::Row(3p), Squirel::Table(3p)

=head1 HISTORY

Started as a quick hack from seeing the hacky template replacement
done by an employer.

It grew.

Largely rewritten in 2012 to avoid processing the same string a few
hundred times.

=cut
