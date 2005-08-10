package DevHelp::Tags;
use strict;

sub make_iterator {
  my ($class, $array, $single, $plural, $saveto) = @_;

  my $index;
  my @result =
      (
       "iterate_${plural}_reset" => sub { $index = -1 },
       $single => 
       sub { 
	 $index >= 0 && $index < @$array 
	   or return "** $single used outside of iterator **";
	 defined($_[0])
	   or return "** no parameter supplied to $single **";
	 my $value = $array->[$index]{$_[0]};
	 defined($value) or return '';
	 return CGI::escapeHTML($value);
       },
       "if\u$plural" => sub { @$array },
       "${single}_index" => sub { $index },
      );
  if ($saveto) {
    return
      (
       @result, 
       "iterate_${plural}" => 
       sub {
	 if (++$index < @$array) {
	   $$saveto = $index;
	   return 1;
	 }
	 return 0;
       },
      );
  }
  else {
    return
      (
       @result, 
       "iterate_${plural}" => 
       sub { ++$index < @$array },
      );
  }
}

sub _iter_reset {
  my ($rdata, $rindex, $code, $loaded, $nocache, $rrow, $args, $acts, $name, $templater) = @_;

  if (!$$loaded && !@$rdata && $code || $args || $nocache) {
    my ($sub, @args) = $code;

    if (ref $code eq 'ARRAY') {
      ($sub, @args) = @$code;
    }
    @$rdata = $sub->(@args, $args, $acts, $name, $templater);
    ++$$loaded unless $args;
  }

  $$rindex = -1;
  defined $rrow and undef $$rrow;

  1;
}

sub _iter_iterate {
  my ($rdata, $rindex, $nocache, $rrow) = @_;

  if (++$$rindex < @$rdata) {
    defined $rrow and $$rrow = $rdata->[$$rindex];
    return 1;
  }
  else {
    defined $rrow and undef $rrow;
    return 0;
  }
}

sub _iter_if {
  my ($rdata, $code, $loaded, $nocache, $args, $acts, $func, $templater) = @_;

  _iter_count($rdata, $code, $loaded, $nocache, $args, $acts, $func, $templater);
}

sub _iter_count {
  my ($rdata, $code, $loaded, $nocache, $args, $acts, $func, $templater) = @_;

  if (!$$loaded && !@$rdata && $code || $args || $nocache) {
    my ($sub, @args) = $code;

    if (ref $code eq 'ARRAY') {
      ($sub, @args) = @$code;
    }
    @$rdata = $sub->(@args, $args, $acts, $func, $templater);
    ++$$loaded unless $args;
  }

  scalar @$rdata;
}

sub _iter_index {
  return ${$_[0]};
}

sub _iter_item {
  my ($rdata, $rindex, $single, $plural, $args) = @_;

  $$rindex >= 0 && $$rindex < @$rdata
    or return "** $single should only be used inside iterator $plural **";
  return $rdata->[$$rindex]{$args};
}

# builds an arrayref based iterator
sub make_iterator2 {
  my ($class, $code, $single, $plural, $rdata, $rindex, $nocache, $rrow) = @_;

  my $index;
  defined $rindex or $rindex = \$index;
  $$rindex = -1;
  $rdata ||= [];
  my $loaded = 0;
  return
    (
     "iterate_${plural}_reset" => 
     [ \&_iter_reset, $rdata, $rindex, $code, \$loaded, $nocache, $rrow ],
     "iterate_${plural}" =>
     [ \&_iter_iterate, $rdata, $rindex, $nocache, $rrow ],
     $single => [ \&_iter_item, $rdata, $rindex, $single, $plural ],
     "if\u$plural" => [ \&_iter_if, $rdata, $code, \$loaded, $nocache ],
     "${single}_index" => [ \&_iter_index, $rindex ],
     "${single}_count" => [ \&_iter_count, $rdata, $code, \$loaded, $nocache ],
    );
}

sub make_dependent_iterator {
  my ($class, $base_index, $getdata, $single, $plural, $saveto) = @_;

  my $last_base = -1;
  my @data;
  my $index;
  my @result =
      (
       "iterate_${plural}_reset" => 
       sub { 
	 if ($$base_index != $last_base) {
	   @data = $getdata->($$base_index);
	   $last_base = $$base_index;
	 }
	 $index = -1
       },
       $single => sub { CGI::escapeHTML($data[$index]{$_[0]}) },
       "if\u$plural" =>
       sub { 
	 if ($$base_index != $last_base) {
	   @data = $getdata->($$base_index);
	   $last_base = $$base_index;
	 }
	 @data
       },
       "${single}_index" => sub { $index },
      );
  if ($saveto) {
    return
      (
       @result, 
       "iterate_${plural}" => 
       sub {
	 if (++$index < @data) {
	   $$saveto = $index;
	   return 1;
	 }
	 return 0;
       },
      );
  }
  else {
    return
      (
       @result, 
       "iterate_${plural}" => 
       sub { ++$index < @data },
      );
  }
}

sub make_multidependent_iterator {
  my ($class, $base_indices, $getdata, $single, $plural, $saveto) = @_;

  # $base_indicies is an arrayref containing scalar refs
  my @last_bases;
  my @data;
  my $index;
  my @result =
      (
       "iterate_${plural}_reset" => 
       sub { 
	 if (join(",", map $$_, @$base_indices) ne join(",", @last_bases)) {
	   @last_bases = map $$_, @$base_indices;
	   @data = $getdata->(@last_bases);
	 }
	 $index = -1
       },
       $single => sub { CGI::escapeHTML($data[$index]{$_[0]}) },
       "if\u$plural" =>
       sub { 
	 if (join(",", map $$_, @$base_indices) ne join(",", @last_bases)) {
	   @last_bases = map $$_, @$base_indices;
	   @data = $getdata->(@last_bases);
	 }
	 @data
       },
       "${single}_index" => sub { $index },
      );
  if ($saveto) {
    return
      (
       @result, 
       "iterate_${plural}" => 
       sub {
	 if (++$index < @data) {
	   $$saveto = $index;
	   return 1;
	 }
	 return 0;
       },
      );
  }
  else {
    return
      (
       @result, 
       "iterate_${plural}" => 
       sub { ++$index < @data },
      );
  }
}

sub tag_date {
  my ($args, $acts, $myfunc, $self) = @_;

  my ($fmt, $func, $funcargs) = 
    $args =~ m/(?:\"([^\"]+)\"\s+)?(\S+)(?:\s+(\S+.*))?/;
  $fmt = "%d-%b-%Y" unless defined $fmt;
  require 'POSIX.pm';
  exists $acts->{$func}
    or return "<:date $args:>";
  my $date = $self->perform($acts, $func, $funcargs)
    or return '';
  my ($year, $month, $day, $hour, $min, $sec) = 
    $date =~ /(\d+)\D+(\d+)\D+(\d+)(?:\D+(\d+)\D+(\d+)\D+(\d+))?/;
  $hour = $min = $sec = 0 unless defined $sec;
  $year -= 1900;
  --$month;
  return POSIX::strftime($fmt, $sec, $min, $hour, $day, $month, $year, 0, 0);
}

sub iter_get_repeat {
  my ($args, $acts, $name, $templater) = @_;

  #print STDERR "iter_get_repeat $args\n";

  my @args = __PACKAGE__->get_parms($args, $acts, $templater);

  my @values;
  if (@args == 2) {
    @values = $args[0] .. $args[1];
  }
  elsif (@args) {
    @values = 1 .. $args[0];
  }
  else {
    return;
  }

  return map { index => $_, value => $values[$_] }, 0..$#values;
}

sub static {
  my ($class) = @_;

  return
    (
     date => \&tag_date,
#       money =>
#       sub {
#         my ($func, $args) = split ' ', $_[0];
#         $args = '' unless defined $args;
#         exists $acts->{$func}
#  	 or return "<: money $func $args :>";
#         my $value = $acts->{$func}->($args);
#         defined $value
#  	 or return '';
#         sprintf("%.02f", $value/100.0);
#       },
     ifEq =>
     sub {
       my @args = __PACKAGE__->get_parms(@_[0,1,3]);
       @args == 2 
	 or do { print STDERR "Not enough args for ifEq\n"; return 0; };
       return $args[0] eq $args[1];
     },
     ifMatch =>
     sub {
       my @args = __PACKAGE__->get_parms(@_[0,1,3]);
       @args == 2
	 or die "Not enough args for ifMatch\n";
       print STDERR "Matching >$args[0]< against >$args[1]<\n";
       $args[0] =~ $args[1];
     },
     __PACKAGE__->make_iterator2(\&iter_get_repeat, 'repeat', 'repeats'),
     _format => 
     sub {
       my ($value, $fmt) = @_;
       if ($fmt eq 'u') {
	 return CGI::escape($value);
       }
       elsif ($fmt eq 'h') {
	 return CGI::escapeHTML($value);
       }
       elsif ($fmt eq 'j') {
	 $value =~ s/(["'&<>\\])/sprintf "\\%03o", ord $1/ge;
         return $value;
       }
       return $value;
     },
    );  
}

# this has been an annoying piece of code
use constant DEBUG_GET_PARMS => 0;

sub get_parms {
  my ($class, $args, $acts, $templater, $keep_unknown) = @_;

  my $orig = $args;

  print STDERR "** Entered get_parms -$args-\n" if DEBUG_GET_PARMS;
  my @out;
  while (length $args) {
    if ($args =~ s/^\s*\[\s*(\w+)
	                (
	                 (?:\s+
			  (?:
			   [^\s\[\]]\S*
			   |
			   \[[^\]\[]+?\]
			  )
			 )*
                        )
	            \s*\]\s*//x) {
      my ($func, $subargs) = ($1, $2);
      $subargs = '' unless defined $subargs;
      if ($acts->{$func}) {
	print STDERR "  Evaluating [$func $subargs]\n" if DEBUG_GET_PARMS;
	my $value = $templater->perform($acts, $func, $subargs);
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

1;
