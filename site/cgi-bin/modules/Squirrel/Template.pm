package Squirrel::Template;
use vars qw($VERSION);
use strict;
use Carp;

$VERSION="0.04";

sub new {
  my ($class, %opts) = @_;

  return bless \%opts, $class;
}

sub perform {
  my ($self, $acts, $func, $args, $orig) = @_;

  $args = '' unless defined $args;
  my $fmt;
  if ($acts->{_format} && $args =~ s/\|([\w%]+)\s*$//) {
    $fmt = $1;
  }

  if (exists $acts->{$func}) {
    $args = '' unless defined $args;
    $args =~ s/^\s+|\s+$//g;
    my $value = $acts->{$func}->($args);
    defined $value
      or return "** function $func $args returned undef **";
    return $fmt ? $acts->{_format}->($value, $fmt) : $value;
  }
  for my $match (keys %$acts) {
    if ($match =~ m(^/(.+)/$)) {
      my $re = $1;
      if ($func =~ /$re/) {
	$args =~ s/^\s+|\s+$//g;
	my $value = $acts->{$match}->($func, $args);
	defined $value
	  or return "** function $func $args returned undef **";
	return $fmt ? $acts->{_format}->($value, $fmt) : $value;
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
       and defined(my $value = $acts->{$newfunc}->($newargs))) {
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

sub iterate {
  my ($self, $name, $args, $input, $sep, $acts, $orig) = @_;

  $args = '' unless defined $args;
  $sep = '' unless defined $sep;

  if (my $entry = $acts->{"iterate_$name"}) {
    $args =~ s/^\s+|\s+$//g;
    my $reset;
    $reset->($args) if $reset = $acts->{"iterate_${name}_reset"};
    my $result = '';
    while ($entry->($name, $args)) {
      $result .= $self->replace_template($sep, $acts) if length $result;
      $result .= $self->replace_template($input, $acts);
    }
    return $result;
  }
  else {
    return $self->{verbose} ? "** No iterator $name **" : $orig;
  }
}

sub cond {
  my ($self, $name, $args, $true, $false, $acts, $orig) = @_;

  if (exists $acts->{"if$name"}) {
    return $acts->{"if$name"}->($args) ? $true : $false;
  }
  elsif (exists $acts->{lcfirst $name}) {
    return $acts->{lcfirst $name}->($args) ? $true : $false;
  }
  else {
    return $orig;
  }
}

sub replace_template {
  my ($self, $template, $acts, $iter) = @_;

  defined $template
    or confess "Template must be defined";

  # add any wrappers
  if ($self->{template_dir}) {
    my $wrap_count = 0;
    while ($template =~ /^(\s*<:\s*wrap\s+(\S+)\s*:>)/i
           && -e "$self->{template_dir}/$2"
           && ++$wrap_count < 10) {
      my $wrapper = "$self->{template_dir}/$2";
      if (open WRAPPER, "< $wrapper") {
        my $wraptext = do { local $/; <WRAPPER> };
        close WRAPPER;
        $template = substr($template, length $1);
        $wraptext =~ s/<:\s*wrap\s+here\s*:>/$template/i
          and $template = $wraptext
            or last;
      }
    }
  }

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
  $template =~ s/(<:\s*iterator\s+begin\s+(\w+)(?:\s+([^:]*))?\s*:>
                  (.*?)
		    (?: 
		     <:\s*iterator\s+separator\s+\2\s*:>
                      (.*?)
		     ) ?
                 <:\s*iterator\s+end\s+\2\s*:>)/
                   $self->iterate($2, $3, $4, $5, $acts, $1) /segx;

  # conditionals
  my $nesting = 0; # prevents loops if result is an if statement
  1 while $template =~ s/(<:\s*if\s+(\w+)(?:\s+([^:]*))?\s*:>
                          (.*?)
                         <:\s*or\s+\2\s*:>
                          (.*?)
                         <:\s*eif\s+\2\s*:>)/
                        $self->cond($2, $3, $4, $5, $acts, $1) /sgex
			  && ++$nesting < 5;
  $template =~ s/(<:\s*if(\w+)(?:\s+([^:]*))?\s*:>
                  (.*?)
                 <:\s*or\s*:>
                  (.*?)
                 <:\s*eif\s*:>)/
                $self->cond($2, $3, $4, $5, $acts, $1) /sgex;

  $template =~ s/(<:\s*(\w+)(?:\s+([^:]*))?\s*:>)/ 
    $self->perform($acts, $2, $3, $1) /egx;

  return $template;
}

sub show_page {
  my ($self, $base, $page, $acts, $iter) = @_;

  $acts ||= {};

  my $file = "$base/$page";
  open TMPLT, "< $file"
    or die "Cannot open template $file: $!";
  my $template = do { local $/; <TMPLT> };
  close TMPLT;

  return $self->replace_template($template, $acts, $iter);
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
L<WRAPPING> below.

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
