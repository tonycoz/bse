package Squirrel::Template;
use vars qw($VERSION);
use strict;
use Carp qw/cluck confess/;
use constant DEBUG => 0;

$VERSION="0.09";

sub new {
  my ($class, %opts) = @_;

  $opts{errout} = \*STDOUT;

  return bless \%opts, $class;
}

sub low_perform {
  my ($self, $acts, $func, $args, $orig) = @_;

  $args = '' unless defined $args;
  my $fmt;
  if ($acts->{_format} && $args =~ s/\|(\S+)\s*$//) {
    $fmt = $1;
  }

  if (exists $acts->{$func}) {
    $args =~ s/^\s+|\s+$//g;
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
  for my $match (keys %$acts) {
    if ($match =~ m(^/(.+)/$)) {
      my $re = $1;
      if ($func =~ /$re/) {
	$args =~ s/^\s+|\s+$//g;
	my $value = $acts->{$match}->($func, $args);
	#defined $value
	#  or return "** function $func $args returned undef **";
	if (defined($value) && $fmt) {
	  $value = $acts->{_format}->($value, $fmt);
	}
	return $value;
      }
    }
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

sub iterator {
  my ($self, $name, $args, $input, $sep, $acts, $orig) = @_;

  $args = '' unless defined $args;
  $sep = '' unless defined $sep;

  print STDERR "iterator $name $args\n" if DEBUG;

  if (my $entry = $acts->{"iterate_$name"}) {
    $args =~ s/^\s+|\s+$//g;

    my $reset = $acts->{"iterate_${name}_reset"};
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
	print STDERR "  resetting (func)\n" if DEBUG > 1;
	$resetf->(@rargs, $args, $acts, $name, $self);
      }
      else {
	my $obj = shift @rargs;
	print STDERR "  resetting (method) $obj->$resetf\n" if DEBUG > 1;
	$obj->$resetf(@rargs, $args, $acts, $name, $self);
      }
      print STDERR "  reset done\n" if DEBUG > 1;
    }
    my $eobj;
    ref $entryf or $eobj = shift @eargs;
    my $result = '';
    while ($eobj ? $eobj->$entryf(@eargs, $name, $args) 
	   : $entryf->(@eargs, $name, $args)) {
      $result .= $self->replace_template($sep, $acts) if length $result;
      $result .= $self->replace_template($input, $acts);
    }
    return $result;
  }
  else {
    return $self->{verbose} ? "** No iterator $name **" : $orig;
  }
}

sub with {
  my ($self, $name, $args, $input, $sep, $acts, $orig) = @_;

  $args = '' unless defined $args;
  if (my $entry = $acts->{"with_$name"}) {
    my $code;
    my @args;
    my $replace = 1;
    if (ref $entry eq 'CODE') {
      $code = $entry;
    }
    elsif (ref $entry eq 'ARRAY') {
      ($code, @args) = @$entry;
    }
    elsif (ref $entry eq 'HASH') {
      $code = $entry->{code};
      @args = @{$entry->{args}} if $entry->{args};
      $replace = $entry->{replace} if exists $entry->{replace};
    }
    else {
      print STDERR "Cannot use '$entry' as a with_$name handler\n";
      return $orig;
    }

    my $result = $input;
    if ($replace) {
      $result = $self->replace_template($result, $acts);
    }

    return $code->(@args, $args, $result, $sep, $acts, $name, $self);
  }
  else {
    return $orig;
  }
}

sub cond {
  my ($self, $name, $args, $acts, $start, $true, $else, $false, $endif) = @_;

  defined $args or $args = '';
  print STDERR "cond $name $args\n" if DEBUG;

  local $SIG{__DIE__};
  my $result =
    eval {
      if (exists $acts->{"if$name"}) {
	print STDERR " found cond if$name\n" if DEBUG > 1;
	my $cond = $self->low_perform($acts, "if$name", $args, '');
	return $cond ? $true : $false;
      }
      elsif (exists $acts->{lcfirst $name}) {
	print STDERR " found cond $name\n" if DEBUG > 1;
	my $cond = $self->low_perform($acts, lcfirst $name, $args, '');
	return $cond ? $true : $false;
      }
      else {
	print STDERR " not found\n" if DEBUG > 1;
	$true = $self->replace_template($true, $acts) if length $true;
	$false = $self->replace_template($false, $acts) if length $false;
	length $args and $args = " " . $args;
	return "$start$args:>$true$else$false$endif";
      }
    };
  if ($@) {
    my $msg = $@;
    if ($msg =~ /\bENOIMPL\b/) {
      print STDERR "Cond ENOIMPL\n" if DEBUG;
      $true = $self->replace_template($true, $acts) if length $true;
      $false = $self->replace_template($false, $acts) if length $false;
      length $args and $args = " " . $args;
      return "$start$args:>$true$else$false$endif";
    }
    print STDERR "Eval error in cond: $msg\n";
    $msg =~ s/([<>&])/"&#".ord($1).";"/ge;
    return "<!-- ** $msg ** -->";
  }

  return $result;
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
    return '' if $options eq 'optional';

    print STDERR "** Could not find include code $name\n";
    return "** cannot find include $name in path **";
  }

  print STDERR "Found $filename\n" if DEBUG;

  open INCLUDE, "< $filename"
    or return "** cannot open $filename : $! **";
  my $data = do { local $/; <INCLUDE> };
  close INCLUDE;
  print STDERR "Included $filename >>$data<<\n"
      if DEBUG;

  $data = "<!-- included $filename -->$data<!-- endinclude $filename -->"
      if DEBUG;

  return $data;
}

sub switch {
  my ($self, $content, $acts) = @_;

  print STDERR "** switch\n" if DEBUG;

  my @cases = split /(?=<:\s*case\s)/s, $content;
  shift @cases if @cases && $cases[0] !~ /<:\s*case\s/;
  my $case;
  while ($case = shift @cases) {
    my ($cond, $data) = $case =~ /<:\s*case\s+(.*?):>(.*)/s;

    if ($cond eq 'default') {
      print STDERR "  returning default\n" if DEBUG;
      return $data;
    }

    my ($func, $args) = split ' ', $cond, 2;

    print STDERR "  testing $func $args\n" if DEBUG;

    local $SIG{__DIE__};
    my $result = 
      eval {
	if (exists $acts->{"if$func"}) {
	  print STDERR "   found cond if$func\n" if DEBUG > 1;
	  return $self->low_perform($acts, "if$func", $args, '');
	}
	elsif (exists $acts->{lcfirst $func}) {
	  print STDERR "   found cond $func\n" if DEBUG > 1;
	  return $self->low_perform($acts, lcfirst $func, $args, '');
	}
	else {
	  print STDERR "   not found\n" if DEBUG > 1;
	  die "ENOIMPL\n";
	}
      };
    if ($@) {
      my $msg = $@;
      $msg =~ /^ENOIMPL\b/
	and return "<:switch:>$case".join("", @cases)."<:endswitch:>";

      print STDERR "Eval error in cond: $msg\n";
      $msg =~ s/([<>&])/"&#".ord($1).";"/ge;
      return "<!-- switch cond $cond ** $msg ** -->";
    }
    print STDERR "    result ",!!$result,"\n" if DEBUG > 1;
    return $data if $result;
  }

  return '';
}

sub tag_param {
  my ($params, $arg) = @_;

  exists $params->{$arg} or return "";

  $params->{$arg};
}

sub replace_template {
  my ($self, $template, $acts, $iter) = @_;

  print STDERR "** >> replace_template\n" if DEBUG;

  defined $template
    or confess "Template must be defined";

  # add any wrappers
  my %params;
  if ($self->{template_dir}) {
    my $wrap_count = 0;
    while ($template =~ /^(\s*<:\s*wrap\s+(\S+?)(?:\s+(\S.*?))?:>)/i) {
      my $name = $2;
      my $wrapper = $self->find_template($name);
      unless ($wrapper) {
	print STDERR "WARNING: Unknown wrap name: $name\n";
	last;
      }
      unless (++$wrap_count < 10) {
	print STDERR "WARNING: Exceeded wrap count trying to load $wrapper\n";
	last;
      }
      my $params = $3;
      if (open WRAPPER, "< $wrapper") {
        my $wraptext = do { local $/; <WRAPPER> };
        close WRAPPER;
        $template = substr($template, length $1);
        $wraptext =~ s/<:\s*wrap\s+here\s*:>/$template/i
          and $template = $wraptext
            or last;

	if (defined $params) {
	  while ($params =~ s/^\s*(\w+)\s*=>\s*\"([^\"]+)\"//
		 || $params =~ s/^\s*(\w+)\s*=>\s*([^\s,]+)//) {
	    my ($name, $value) = ($1, $2);
	    $value =~ s/(\[\s*
                         (\w+)  # tag name
                           (?:  # followed optionally by
                            \s+  # white space
                              (  # and some parameters
                                ([^\]\s]
                                  (?:[^\]\[]*[^\]\s])?
                                )
                              )
                            )?
                         \s*\])/ $self->perform($acts, $2, $3, $1) /egsx;

	    $params{$name} = $value;
	    $params =~ s/\s*,\s*//;
	  }
	  $params =~ /^\s*$/
	    or print STDERR "WARNING: Extra data after parameters '$params'\n";
	}
      }
      else {
	print "ERROR: Unable to load wrapper $wrapper: $!\n";
      }
    }
  }

  my $oldparam_tag = $acts->{param};
  local $acts->{param} = $oldparam_tag || [ \&tag_param, \%params ];

  if ($self->{template_dir} && !$acts->{include}) {
    my $loops = 0;
    1 while $template =~
            s!<:
                \s*
                include
                \s+
                ((?:\w+/)*\w+(?:\.\w+)?)
                (?:
                  \s+
                  ([\w,]+)
                )?
                \s*
               :>
             ! 
               $self->include($1,$2) 
             !gex
	       && ++$loops < 10;
  }

  print STDERR "Template text post include:\n---$template---\n"
    if DEBUG;

  # the basic iterator
  if ($iter && 
      (my ($before, $row, $after) =
      $template =~ m/^(.*)
           <:\s+iterator\s+begin\s+:>
            (.*)
           <:\s+iterator\s+end\s+:>
            (.*)/sx)) {
    until ($iter->EOF) {
      my $temp = $row;
      $temp =~ s/(<:\s*(\w+)(?:\s+([^:]*?))\s*:>)/ $self->perform($acts, $2, $3, $1) /egx;
      $before .= $temp;
    }
    $template = $before . $after;
  }

  # more general iterators
  $template =~ s/(<:\s*(iterator|with)\s+begin\s+(\w+)(?:\s+(.*?))?\s*:>
                  (.*?)
		    (?: 
		     <:\s*\2\s+separator\s+\3\s*:>
                      (.*?)
		     ) ?
                 <:\s*\2\s+end\s+\3\s*:>)/
                   $self->$2($3, $4, $5, $6, $acts, $1) /segx;

  # conditionals
  my $nesting = 0; # prevents loops if result is an if statement
  1 while $template =~ s/(<:\s*if\s+(\w+))(?:\s+(.*?))?\s*:>
                          (.*?)
                         (<:\s*or\s+\2\s*:>)
                          (.*?)
                         (<:\s*eif\s+\2\s*:>)/
                        $self->cond($2, $3, $acts, $1, $4, $5, $6, $7) /sgex
			  && ++$nesting < 5;
  $template =~ s/(<:\s*if([A-Z]\w*))(?:\s+(.*?))?\s*:>
                  (.*?)
                 (<:\s*or\s*:>)
                  (.*?)
                 (<:\s*eif\s*:>)/
                $self->cond($2, $3, $acts, $1, $4, $5, $6, $7) /sgex;

  $nesting = 0;
  1 while $template =~ s/<:\s*switch\s*:>
                         ((?!<:\s*switch).*?)
                         <:\s*endswitch\s*:>/
			   $self->switch($1, $acts)/segx
			     && ++$nesting < 5;

  $template =~ s/(<:\s*(\w+)(?:\s+(.*?))?\s*:>)/ 
    $self->perform($acts, $2, $3, $1) /segx;

  # replace any wrap parameters
  # now done elsewhere
  #$template =~ s/(<:\s*param\s+(\w+)\s*:>)/
  #  exists $params{$2} ? $params{$2} : $1 /eg;


  print STDERR "** << replace_template\n" if DEBUG;

  return $template;
}

sub show_page {
  my ($self, $base, $page, $acts, $iter, $alt) = @_;

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
  open TMPLT, "< $file"
    or die "Cannot open template $file: $!";
  my $template = do { local $/; <TMPLT> };
  close TMPLT;

  my $result = $self->replace_template($template, $acts, $iter);
  print STDERR "<< show_page\n" if DEBUG;

  return $result;
}

1;

__END__

=head1 NAME

  Squirrel::Template - simple templating system

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 METHODS

=over 4

=item $templ = Squirrel::Template->new(%opts);

Create a new templating object.

Possible options are:

=over 4

=item verbose

If a tag isn't found in the actions then it is replaced with an error
message rather than being left in place.

=item template_dir

Used by the wrapper mechanism to find wrapper templates.  See
L<WRAPPING> below.  This can be either a scalar, or a reference to an
array of locations to search for the wrapper.  This is also used for
the <:include filename:> mechanism.

=back

=item $text = $templ->show_page($base, $template, $acts, $iter)

Performs template replacement on the text from the file $template in
directory $base.

=item $text = $templ->replace_template($intext, $acts, $iter)

Performs template replacement on $intext.

=back

=head1 TEMPLATES

=over 4

=item <: name args :>

Replaced with $acts->{name}->(args)

=item <: iterator begin name args :> text <: iterator separator name :> separator <: iterator end name :>

Replaced with repeated templating of text separated by separator while
$acts->{iterator_name}->($args, $name) is true.


=item <: iterator begin name args :> text <: iterator end name :>

Replaced with repeated templating of text while
$acts->{iterate_name}->($args, $name) is true.

This may be nested or repeated.

=item <: iterator begin :> text <: iterator end :>

Replaced with repeated templating of text while $iter->EOF is true.

=item <: ifname args :> true <: or :> false <: eif :>

Emits true if $acts->{ifname}->($args) is true, otherwise the false text.

=item <: if name args :> true <: or name :> false <: eif name :>

Emits true if $acts->{ifname}->($args) is true, otherwise the false text.

Has the advantage that it can be nested (the other form doesn't
support nesting - this isn't a proper parser.

=back

=head1 WRAPPING

If you define the template_dir option when you create your templating
object, then a mechnism to wrap the current template with another is
enabled.

For the wrapping to occur:

=over 4

=item *

The template specified in the call to replace_template() or
show_page() needs to start with:

<: wrap I<templatename> :>

=item *

The template specified in the <: wrap ... :> tag must exist in the
directory specified by the I<template_dir> option.

=item *

The template specified in the <: wrap ... :> tag must contain a:

   <: wrap here :>

tag.

=back

The current template text is then replaced with the contents of the
template specified by I<templatename>, with the <: wrap here :>
replaced by the original template text.

This is then repeated for the new template text.

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

=cut
