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

sub static {
  my ($class, $acts) = @_;

  return
    (
     date =>
     sub {
       my ($fmt, $func, $args) = 
	 $_[0] =~ m/(?:\"([^\"]+)\"\s+)?(\S+)(?:\s+(\S+.*))?/;
       $fmt = "%d-%b-%Y" unless defined $fmt;
       require 'POSIX.pm';
       exists $acts->{$func}
	 or return "<:date $_[0]:>";
       my $date = $acts->{$func}->($args)
	 or return '';
       my ($year, $month, $day, $hour, $min, $sec) = 
	 $date =~ /(\d+)\D+(\d+)\D+(\d+)(?:\D+(\d+)\D+(\d+)\D+(\d+))?/;
       $hour = $min = $sec = 0 unless defined $sec;
       $year -= 1900;
       --$month;
       return POSIX::strftime($fmt, $sec, $min, $hour, $day, $month, $year, 0, 0);
     },
     money =>
     sub {
       my ($func, $args) = split ' ', $_[0];
       $args = '' unless defined $args;
       exists $acts->{$func}
	 or return "<: money $func $args :>";
       my $value = $acts->{$func}->($args);
       defined $value
	 or return '';
       sprintf("%.02f", $value/100.0);
     },
     ifEq =>
     sub {
       (my ($left, $right) = _get_parms($acts, $_[0])) == 2
	 or die; # leaves if in place
       $left eq $right;
     },
     ifMatch =>
     sub {
       (my ($left, $right) = _get_parms($acts, $_[0])) == 2
	 or die; # leaves if in place
       $left =~ $right;
     },
     _format => 
     sub {
       my ($value, $fmt) = @_;
       if ($fmt eq 'u') {
	 return CGI::escape($value);
       }
       elsif ($fmt eq 'h') {
	 return CGI::escapeHTML($value);
       }
       return $value;
     },
    );  
}

1;
