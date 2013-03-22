package Squirrel::Template::Processor;
use strict;
use Squirrel::Template::Constants qw(:node);
use Scalar::Util ();

our $VERSION = "1.022";

use constant ACTS => 0;
use constant TMPLT => 1;
use constant PARMS => 2;
use constant WRAPPED => 3;
use constant EVAL => 4;

sub new {
  my ($class, $acts, $tmplt, $wrapped) = @_;

  return bless 
    [
     $acts,
     $tmplt,
     {},
     $wrapped,
     Squirrel::Template::Expr::Eval->new($tmplt, $acts)
    ], $class;
}

# return an error node matching the supplied node
sub _error {
  my ($self, $node, $message) = @_;

  my $error = [ error => "", $node->[NODE_LINE], $node->[NODE_FILENAME], $message ];

  return $self->_process_error($error);
}

sub process {
  my ($self, $node) = @_;

  my $method = "_process_$node->[NODE_TYPE]";
  return $self->$method($node);
}

sub _process_content {
  my ($self, $node) = @_;

  return $node->[NODE_ORIG];
}

sub _process_empty {
  my ($self, $node) = @_;

  return;
}

sub _process_stmt {
  my ($self, $node) = @_;

  my @errors;
  my $value = "";
  unless (eval {
    for my $expr (@{$node->[NODE_EXPR_EXPR]}) {
      $self->[EVAL]->process($expr);
    }
    1;
  }) {
    my $msg = $@;

    if ($msg =~ /\bENOIMPL\b/) {
      $self->[TMPLT]->trace_noimpl("stmt:$node->[NODE_FILENAME]:$node->[NODE_LINE]:$msg\n");
      return $node->[NODE_ORIG];
    }

    push @errors, $self->_error($node, ref $msg ? $msg->[1] : $msg );
  }

  return ( @errors );
}

sub _process_expr {
  my ($self, $node) = @_;

  my @errors;
  my $value = "";
  unless (eval { $value = $self->[EVAL]->process($node->[NODE_EXPR_EXPR]); 1 }) {
    my $msg = $@;

    if ($msg =~ /\bENOIMPL\b/) {
      $self->[TMPLT]->trace_noimpl("expr:$node->[NODE_FILENAME]:$node->[NODE_LINE]:$msg\n");
      return $node->[NODE_ORIG];
    }

    push @errors, $self->_error($node, ref $msg ? $msg->[1] : $msg );
  }
  defined $value
    or $value = '';
  if ($node->[NODE_EXPR_FORMAT]) {
    $value = $self->[TMPLT]->format($value, $node->[NODE_EXPR_FORMAT]);
  }
  return ( @errors, $value );
}

sub _process_set {
  my ($self, $node) = @_;

  my @errors;
  my $value = "";
  if (eval { $value = $self->[EVAL]->process($node->[NODE_SET_EXPR]); 1 }) {
    my @var = @{$node->[NODE_SET_VAR]};
    if (@var > 1) {
      my $top_name = shift @var;
      my $var = $self->[TMPLT]->get_var($top_name);
      unless ($var) {
	$var = {};
	$self->[TMPLT]->set_var($top_name, $var);
      }
      my @seen = $top_name;
      while (@var > 1) {
	my $subkey = shift @var;
	Scalar::Util::blessed($var)
	    and die [ error => "Cannot set values in an object ".join(".", @seen) ];
	my $type = Scalar::Util::reftype($var);
	if ($type eq 'HASH') {
	  exists $type->{$subkey}
	    or die [ error => "$subkey not found in ".join(".", @seen) ];
	  $var = $var->{$subkey};
	  push @seen, $subkey;
	}
	else {
	  die [ error => "Only hashes supported for now" ];
	}
      }
      Scalar::Util::blessed($var)
	  and die [ error => "Cannot set values in an object ".join(".", @seen) ];
      ref $var
	or die [ error => join(".", @seen) . " isn't a reference" ];
      Scalar::Util::reftype($var) eq 'HASH'
	or die [ error => "Only hashes supported for now" ];
      $var->{$var[0]} = $value;
    }
    else {
      $self->[TMPLT]->set_var($var[0] => $value);
    }
  }
  else {
    my $msg = $@;

    if ($msg =~ /\bENOIMPL\b/) {
      $self->[TMPLT]->trace_noimpl("set:$node->[NODE_FILENAME]:$node->[NODE_LINE]:$msg\n");
      return $node->[NODE_ORIG];
    }

    push @errors, $self->_error($node, ref $msg ? $msg->[1] : $msg );
  }

  return @errors;
}

sub _process_define {
  my ($self, $define) = @_;

  $self->[TMPLT]->define_macro($define->[NODE_DEFINE_NAME], $define->[NODE_DEFINE_CONTENT]);

  return;
}

sub _process_call {
  my ($self, $node) = @_;

  my $parsed;
  my %args;
  my @result;
  my $name;
  if (eval {
    $name = $self->[EVAL]->process($node->[NODE_CALL_NAME]);
    for my $arg (@{$node->[NODE_CALL_LIST]}) {
      my $key = $self->[EVAL]->process($arg->[0]);
      my $value = $self->[EVAL]->process($arg->[1]);
      $args{$key} = $value;
    }

    $parsed = $self->[TMPLT]->get_macro($name);
    if (!$parsed) {
      ($parsed, my $message) = $self->[TMPLT]->parse_file($name);
      unless ($parsed) {
	$self->[TMPLT]->trace_noimpl("call:$node->[NODE_FILENAME]:$node->[NODE_LINE]:$message\n");
	die "ENOIMPL - $name not found\n";
      }
    }
    1;
  }) {
    my $ctx = ".call '$name' from $node->[NODE_FILENAME]:$node->[NODE_LINE]";
    if (eval { $self->[TMPLT]->start_scope($ctx, \%args), 1 }) {
      @result = $self->process($parsed);
      $self->[TMPLT]->end_scope();
    }
    else {
      my $error = $@;
      chomp $error;
      push @result,
	"Error opening scope for call: $error\nBacktrace:\n",
	  map {; "  ", $_, "\n" } ( reverse $self->[TMPLT]->backtrace );
    }
  }
  else {
    @result = $node->[NODE_ORIG];
  }

  return @result;
}

sub _process_for {
  my ($self, $node) = @_;

  my $list;
  unless (eval {
    $list = $self->[EVAL]->process($node->[NODE_FOR_EXPR]); 1;
  }) {
    my $msg = $@;
    if ($msg =~ /\bENOIMPL\b/) {
      return
	(
	 $node->[NODE_ORIG],
	 $self->process($node->[NODE_FOR_CONTENT]),
	 $node->[NODE_FOR_END][NODE_ORIG]
	);
    }
    else {
      return $self->_error($node, $@);
    }
  }

  if (ref $list) {
    Scalar::Util::blessed($list)
	and return $self->_error($node, ".for expression cannot be a blessed object");

    if (Scalar::Util::reftype($list) eq "ARRAY") {
      # nothing to do
    }
    elsif (Scalar::Util::reftype($list) eq "HASH") {
      my @work = map +{ key => $_, value => $list->{$_} }, keys %$list;
      $list = \@work;
    }
    else {
      return $self->_error($node, ".for expression cannot be a blessed object");
    }
  }
  else {
    $list = [ $list ];
  }

  my $index = 0;
  my %loop =
    (
     first => @$list ? $list->[0] : undef,
     last => @$list ? $list->[-1] : undef,
     size => scalar @$list,
     is_last => sub { $index == $#$list },
     is_first => sub { $index == 0 },
     count => sub { $index + 1 },
     index => sub { $index },

     # the parity/odd/even are based on counting from 1, $index counts
     # from zero
     parity => sub { $index % 2 ? "even" : "odd" },
     odd => sub { $index % 2 == 0 },
     even => sub { $index % 2 != 0 },

     prev => sub { $index > 0 ? $list->[$index-1] : undef },
     next => sub { $index < $#$list ? $list->[$index+1] : undef },
     list => $list,
    );
  my $name = $node->[NODE_FOR_NAME];

  my $scope = $self->[TMPLT]->top_scope;
  local $scope->{$name};
  local $scope->{loop} = \%loop;

  my @result;
  for my $current (@$list) {
    $scope->{$name} = $current;
    $loop{current} = $current;
    push @result, $self->process($node->[NODE_FOR_CONTENT]);
    ++$index;
  }

  return @result;
}

sub _process_error {
  my ($self, $node) = @_;

  return "* " . $node->[NODE_ERROR_MESSAGE] . " *";
}

sub _process_cond {
  my ($self, $node) = @_;

  local $SIG{__DIE__};
  my $acts = $self->[ACTS];
  my $cond;
  my $name = $node->[NODE_TAG_NAME];
  my @errors;
  my $result =
    eval {
      if (exists $acts->{"if$name"}) {
	#print STDERR " found cond if$name\n" if DEBUG > 1;
	$cond = !!$self->[TMPLT]->low_perform($acts, "if$name", $node->[NODE_TAG_ARGS], undef);
      }
      elsif (exists $acts->{lcfirst $name}) {
	#print STDERR " found cond $name\n" if DEBUG > 1;
	$cond = !!$self->[TMPLT]->low_perform($acts, lcfirst $name, $node->[NODE_TAG_ARGS], undef);
      }
    };
  if ($@) {
    my $msg = $@;
    if ($msg !~ /\bENOIMPL\b/) {
      @errors = $self->_error($node, $msg);
    }
  }
  if (defined $cond) {
    return (@errors, $self->process($cond ? $node->[NODE_COND_TRUE]
				    : $node->[NODE_COND_FALSE]));
  }
  else {
    return (@errors, $node->[NODE_ORIG], $self->process($node->[NODE_COND_TRUE]), $node->[NODE_COND_OR][NODE_ORIG], $self->process($node->[NODE_COND_FALSE]), $node->[NODE_COND_EIF][NODE_ORIG]);
  }
}

sub _process_condnot {
  my ($self, $node) = @_;

  local $SIG{__DIE__};
  my $acts = $self->[ACTS];
  my $cond;
  my $name = $node->[NODE_TAG_NAME];
  my @errors;
  my $result =
    eval {
      if (exists $acts->{"if$name"}) {
	#print STDERR " found cond if$name\n" if DEBUG > 1;
	$cond = !!$self->[TMPLT]->low_perform($acts, "if$name", $node->[NODE_TAG_ARGS], undef);
      }
      elsif (exists $acts->{lcfirst $name}) {
	#print STDERR " found cond $name\n" if DEBUG > 1;
	$cond = !!$self->[TMPLT]->low_perform($acts, lcfirst $name, $node->[NODE_TAG_ARGS], undef);
      }
    };
  if ($@) {
    my $msg = $@;
    if ($msg !~ /\bENOIMPL\b/) {
      @errors = $self->_error($node, $msg);
    }
  }
  if (defined $cond) {
    return (@errors, $cond ? "" : $self->process($node->[NODE_COND_TRUE]));
  }
  else {
    return (@errors, $node->[NODE_ORIG], $self->process($node->[NODE_COND_TRUE]), $node->[NODE_COND_EIF][NODE_ORIG]);
  }
}

sub _process_iterator {
  my ($self, $node) = @_;

  my $name = $node->[NODE_TAG_NAME];
  my $args = $node->[NODE_TAG_ARGS];

  my $entry = $self->[ACTS]{"iterate_$name"};
  if ($entry) {
    my $reset = $self->[ACTS]{"iterate_${name}_reset"};
    my ($resetf, @rargs);
    if ($reset) {
      if (ref $reset eq 'ARRAY') {
	($resetf, @rargs) = @$reset;
      }
      else {
	$resetf = $reset;
      }
    }

    my ($entryf, @eargs);
    if (ref $entry eq 'ARRAY') {
      ($entryf, @eargs) = @$entry;
    }
    else {
      $entryf = $entry;
    }

    if ($resetf) {
      if (ref $resetf) {
	#print STDERR "  resetting (func)\n" if DEBUG > 1;
	$resetf->(@rargs, $args, $self->[ACTS], $name, $self->[TMPLT]);
      }
      else {
	my $obj = shift @rargs;
	#print STDERR "  resetting (method) $obj->$resetf\n" if DEBUG > 1;
	$obj->$resetf(@rargs, $args, $self->[ACTS], $name, $self->[TMPLT]);
      }
      #print STDERR "  reset done\n" if DEBUG > 1;
    }
    my $eobj;
    ref $entryf or $eobj = shift @eargs;
    my @result;
    my $index = 0;
    while ($eobj ? $eobj->$entryf(@eargs, $name, $args)
	   : $entryf->(@eargs, $name, $args)) {
      push @result, $self->process($node->[NODE_ITERATOR_SEPARATOR])
	if $index;
      push @result, $self->process($node->[NODE_ITERATOR_LOOP]);
      ++$index;
    }
    return @result;
  }
  else {
    return
      (
       $node->[NODE_ORIG],
       $self->process($node->[NODE_ITERATOR_LOOP]),
       $node->[NODE_ITERATOR_SEPTOK][NODE_ORIG],
       $self->process($node->[NODE_ITERATOR_SEPARATOR]),
       $node->[NODE_ITERATOR_ENDTOK][NODE_ORIG]
      );
  }
}

sub _process_with {
  my ($self, $node) = @_;

  my $name = $node->[NODE_TAG_NAME];
  my $args = $node->[NODE_TAG_ARGS];

  my $entry = $self->[ACTS]{"with_$name"};
  if ($entry) {
    my ($code, @args);
    if (ref $entry eq 'ARRAY') {
      ($code, @args) = @$entry;
    }
    else {
      $code = $entry;
    }

    my $obj;
    ref $code or $obj = shift @args;
    my $work = join('', $self->process($node->[NODE_WITH_CONTENT]));
    return $obj
      ? $obj->$code(@args, $args, $work, "", $self->[ACTS], $name, $self->[TMPLT])
	: $code->(@args, $args, $work, "", $self->[ACTS], $name, $self->[TMPLT]);
  }
  else {
    return
      (
       $node->[NODE_ORIG],
       $self->process($node->[NODE_WITH_CONTENT]),
       $node->[NODE_WITH_END][NODE_ORIG]
      );
  }
}

sub _process_wrap {
  my ($self, $node) = @_;

  my ($filename, $args, $content) =
    @{$node}[NODE_WRAP_FILENAME, NODE_WRAP_ARGS, NODE_WRAP_CONTENT];

  my %params;
  my $parms_re = $self->[TMPLT]->parms_re;

  my @errors;
  while ($args =~ s/^\s*(\w+)\s*=>\s*\"([^\"]+)\"//
	 || $args =~ s/^\s*(\w+)\s*=>\s*($parms_re)//
	 || $args =~ s/^\s*(\w+)\s*=>\s*([^\s,]+)//) {
    my ($name, $value) = ($1, $2);
    $value =~ s/\A($parms_re)\z/ $self->[TMPLT]->perform($self->[ACTS], $2, $3, $1) /egs;

    $params{$name} = $value;
    $args =~ s/\s*,\s*//;
  }
  $args =~ /^\s*$/
    or push @errors, $self->_error($node, "WARNING: Extra data after parameters '$args'");

  my @result;
  if ($self->[TMPLT]->start_wrap(\%params)) {
    my ($wrap_node, $error) = $self->[TMPLT]->parse_file($node->[NODE_WRAP_FILENAME]);

    if ($wrap_node) {
      my $proc = __PACKAGE__->new($self->[ACTS], $self->[TMPLT],
				  sub { $self->process($content) });

      push @result, $proc->process($wrap_node);
    }
    else {
      push @result, $self->_error($node, "Loading wrap: $error");
    }
    $self->[TMPLT]->end_wrap;
  }
  else {
    push @errors, $self->_error($node, "Error starting wrap: Too many levels of wrap for '$node->[NODE_WRAP_FILENAME]'");
    @result = $self->process($content);
  }

  return ( @errors, @result );
}

sub _process_wraphere {
  my ($self, $node) = @_;

  $self->[WRAPPED]
    or return $self->_error($node, "wrap here without being wrapped");

  return $self->[WRAPPED]->();
}

sub _process_switch {
  my ($self, $node) = @_;

  my $cases = $node->[NODE_SWITCH_CASES];
  my @errors;
  for my $i (0 .. $#$cases) {
    my ($case, $content) = @{$cases->[$i]};

    my ($type, $func, $args) =
      @{$case}[NODE_TYPE, NODE_TAG_NAME, NODE_TAG_ARGS];

    if ($func eq "default") {
      return $self->process($content);
    }

    my $result;
    my $good = 
      eval {
	local $SIG{__DIE__};

	if (exists $self->[ACTS]{"if$func"}) {
	  $result = $self->[TMPLT]->low_perform($self->[ACTS], "if$func", $args, "");
	}
	elsif (exists $self->[ACTS]{lcfirst $func}) {
	  $result = $self->[TMPLT]->low_perform($self->[ACTS], lcfirst $func, $args, '');
	}
	else {
	  die "ENOIMPL $func not found for switch case\n";
	}
	1;
      };
    unless ($good) {
      my $msg = $@;
      if ($msg =~ /^ENOIMPL\b/) {
	return
	  (
	   @errors,
	   $node->[NODE_ORIG],
	   (
	    map {
	      $_->[0][NODE_ORIG], $self->process($_->[1])
	    } @{$cases}[$i .. $#$cases ]
	   ),
	   $node->[NODE_SWITCH_END][NODE_ORIG],
	  );
      }
      push @errors, $self->_error($case, $msg);
    }
    if ($type eq 'case' ? $result : !$result) {
      return (@errors, $self->process($content));
    }
  }

  return @errors;
}

sub _process_ext_if {
  my ($self, $node) = @_;

  my @conds = @{$node->[NODE_EXTIF_CONDS]};
  while (my $cond = shift @conds) {
    my $result;
    if (eval { $result = $self->[EVAL]->process($cond->[2]); 1 }) {
      if ($result) {
	return $self->process($cond->[1]);
      }
    }
    else {
      my $msg = $@;
      if (!ref $msg && $msg =~ /\bENOIMPL\b/) {
	unshift @conds, $cond;

	my $prefix = '';
	if (@conds < @{$node->[NODE_EXTIF_CONDS]}) {
	  $prefix = "<:.if 0 :>";
	}

	return
	  (
	   $prefix,
	   (
	    map { $_->[0][NODE_ORIG], $self->process($_->[1]) } @conds
	   ),
	   $node->[NODE_EXTIF_ELSE][0][NODE_ORIG],
	   $self->process($node->[NODE_EXTIF_ELSE][1]),
	   $node->[NODE_EXTIF_END][NODE_ORIG]
	  );
      }
      else {
	return $self->_error($node, ref $msg ? $msg->[1] : $msg);
      }
    }
  }

  return $self->process($node->[NODE_EXTIF_ELSE][1]);
}

sub _process_comp {
  my ($self, $node) = @_;

  return map $self->process($_), @{$node}[NODE_COMP_FIRST .. $#$node];
}

sub _process_tag {
  my ($self, $node) = @_;

  my $name = $node->[NODE_TAG_NAME];
  my $replaced = 0;
  my $tag_method = "tag_$name";
  if (exists $self->[ACTS]{$name} || $self->[TMPLT]->can($tag_method)) {
    my $value;
    if (eval { $value = $self->[TMPLT]->low_perform($self->[ACTS], $name, $node->[NODE_TAG_ARGS], $node->[NODE_ORIG]); 1 }) {
      return $value;
    }
    my $msg = $@;
    unless ($msg =~ /\bENOIMPL\b/) {
      return $self->_error($node, $msg);
    }
  }

  return Squirrel::Template::Deparser->deparse($node);
}

sub _process_iterateover {
  my ($self, $node) = @_;

  my $call;
  my @args;
  unless (eval {
    $call = $self->[EVAL]->process($node->[NODE_ITERATEOVER_CALL]);
    @args = map $self->[EVAL]->process($_), @{$node->[NODE_ITERATEOVER_ARGS]};
    1;
  }) {
    my $msg = $@;
    if ($msg =~ /\bENOIMPL\b/) {
      return
	(
	 $node->[NODE_ORIG],
	 $self->process($node->[NODE_FOR_CONTENT]),
	 $node->[NODE_FOR_END][NODE_ORIG]
	);
    }
    else {
      return $self->_error($node, $@);
    }
  }

  unless (ref $call && !Scalar::Util::blessed($call)
	  && Scalar::Util::reftype($call) eq 'CODE') {
    return $self->_error($node, ".iterateover expression must be a code reference");
  }

  my @result;
  unless (eval {
    $call->
      (
       sub {
	 push @result, $self->process($node->[NODE_ITERATEOVER_CONTENT]);
	 1;
       },
       $self->[TMPLT],
       @args
      );
    1;
  }) {
    push @result, $self->_error($node, "exception in .iterateover callback ".$@);
  }

  return @result;
}

sub _process_while {
  my ($self, $node) = @_;

  my $cond = $node->[NODE_WHILE_COND];
  my $result;
  unless (eval { $result = $self->[EVAL]->process($cond); 1 }) {
    my $msg = $@;
    if (!ref $msg && $msg ==~ /\bENOIMPL\b/) {
      return
	(
	 $node->[NODE_ORIG],
	 $self->process($node->[NODE_WHILE_CONTENT]),
	 $node->[NODE_WHILE_END][NODE_ORIG],
	);
    }
    else {
      return $self->_error($node, ref $msg ? $msg->[1] : $msg);
    }
  }
  my @output;
  while ($result) {
    push @output, $self->process($node->[NODE_WHILE_CONTENT]);

    unless (eval { $result = $self->[EVAL]->process($cond); 1 }) {
      my $msg = $@;
      if (!ref $msg && $msg ==~ /\bENOIMPL\b/) {
	return
	  (
	   @output,
	   $node->[NODE_ORIG],
	   $self->process($node->[NODE_WHILE_CONTENT]),
	   $node->[NODE_WHILE_END][NODE_ORIG],
	  );
      }
      else {
	return
	  (
	   @output,
	   $self->_error($node, ref $msg ? $msg->[1] : $msg),
	  );
      }
    }
  }

  return @output;
}

1;

=head1 NAME

Squirrel::Template::Processor - process a parsed template

=head1 SYNOPSIS

  use Squirrel::Template;
  my $tmpl = Squirrel::Template->new(...);
  my $proc = Squirrel::Template::Processor->new(\%acts, $tmpl);
  my @content = $proc->process($node);

=head1 DESCRIPTION

Processes a parsed template node producing text.

Calls back into the templater to find and parse wrapper files, to set
wrap parameters and  to evaluate some tags.

=head1 METHODS

=over

=item new(\%acts, $tmpl)

Create a new processor.  A third C<$wrapped> parameter can be supplied
when processing wrapped subtemplates.

=item process($node)

Process a parsed template node returning the results as a list.

=back

=head1 AUTHOR

Tony Cook <tony@develop-help.com>

=cut
