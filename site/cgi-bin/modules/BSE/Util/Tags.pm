package BSE::Util::Tags;
use strict;
use HTML::Entities;
use DevHelp::Tags;

sub _get_parms {
  my ($acts, $args) = @_;

  my @out;
  while (length $args) {
    if ($args =~ s/^\s*\[\s*(\w+)(?:\s+(\S[^\]]*))?\]\s*//) {
      my ($func, $subargs) = ($1, $2);
      if ($acts->{$func}) {
	$subargs = '' unless defined $subargs;
	push(@out, $acts->{$func}->($subargs));
      }
    }
    elsif ($args =~ s/^\s*\"((?:[^\"\\]|\\[\\\"])*)\"\s*//) {
      my $out = $1;
      $out =~ s/\\([\\\"])/$1/g;
      push(@out, $out);
    }
    elsif ($args =~ s/^\s*(\S+)\s*//) {
      push(@out, $1);
    }
    else {
      last;
    }
  }

  @out;
}

sub static {
  my ($class, $acts, $cfg) = @_;

  return
    (
     date =>
     sub {
       my ($arg, $acts, $name, $templater) = @_;
       my ($fmt, $func, $args) = 
	 $arg =~ m/(?:\"([^\"]+)\"\s+)?(\S+)(?:\s+(\S+.*))?/;
       $fmt = "%d-%b-%Y" unless defined $fmt;
       require 'POSIX.pm';
       exists $acts->{$func}
	 or return "<:date $_[0]:>";
       my $date = $templater->perform($acts, $func, $args)
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
       my ($arg, $acts, $name, $templater) = @_;
       my ($func, $args) = split ' ', $arg;
       $args = '' unless defined $args;
       exists $acts->{$func}
	 or return "<: money $func $args :>";
       my $value = $templater->perform($acts, $func, $args);
       defined $value
	 or return '';
       sprintf("%.02f", $value/100.0);
     },
     bodytext =>
     sub {
       my ($arg, $acts, $name, $templater) = @_;
       my ($func, $args) = split ' ', $arg, 2;

       $args = '' unless defined $args;
       exists $acts->{$func}
	 or return "<: bodytext $func $args :>";
       my $value = $templater->perform($acts, $func, $args);
       defined $value
	 or return '';
       
       $value = decode_entities($value);
       require 'Generate.pm';
       my $gen = Generate->new;
       
       return $gen->format_body($acts, 'Articles', $value, 'tr', 0);
     },
     ifEq =>
     sub {
       my ($arg, $acts, $name, $templater) = @_;
       (my ($left, $right) = DevHelp::Tags->get_parms($arg, $acts, $templater)) == 2
	 or die; # leaves if in place
       #print STDERR "ifEq >$left< >$right<\n";
       $left eq $right;
     },
     ifMatch =>
     sub {
       my ($arg, $acts, $name, $templater) = @_;
       (my ($left, $right) = DevHelp::Tags->get_parms($arg, $acts, $templater)) == 2
	 or die; # leaves if in place
       $left =~ $right;
     },
     cfg =>
     sub {
       my ($section, $key, $def) = split ' ', $_[0];
       $cfg or return '';
       my $value = $cfg->entry($section, $key);
       unless (defined $value) {
	 $value = defined($def) ? $def : '';
       }
       $value;
     },
     kb =>
     sub {
       my ($arg, $acts, $name, $templater) = @_;
       my ($key, $args) = split ' ', $arg, 2;
       $acts->{$key} or return "<:kb $arg:>";
       my $value = $templater->perform($acts, $key, $args);
       if ($value > 100000) {
         return sprintf("%.0fk", $value/1000.0);
       }
       elsif ($value > 1000) {
         return sprintf("%.1fk", $value/1000.0);
       }
       else {
         return $value;
       }
     },
     release =>
     sub {
       require BSE::Version;
       BSE::Version->version;
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

sub basic {
  my ($class, $acts, $cgi, $cfg) = @_;

  return
    (
     $class->static($acts, $cfg),
     script =>
     sub {
       $ENV{SCRIPT_NAME}
     },
     cgi =>
     sub {
       $cgi or return '';
       my @value = $cgi->param($_[0]);
       CGI::escapeHTML("@value");
     },
    );
}

sub make_iterator {
  my ($class, $array, $single, $plural, $saveto) = @_;

  my $index;
  my @result =
      (
       "iterate_${plural}_reset" => sub { $index = -1 },
       $single => sub { CGI::escapeHTML($array->[$index]{$_[0]}) },
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

sub admin {
  my ($class, $acts, $cfg) = @_;

  return
    (
     help =>
     sub {
       my ($file, $entry) = split ' ', $_[0];

#       qq!<a href="/admin/help/$file.html#$entry" target="_blank"><img src="/images/admin/help.gif" width="16" height="16" border="0" /></a>!;
       return <<HTML;
<a href="#" onClick="window.open('/admin/help/$file.html#$entry', 'adminhelp', 'width=400,height=300,location=no,status=no,menubar=no,scrollbars=yes'); return 0;"><img src="/images/admin/help.gif" width="16" height="16" border="0" alt="help on $entry" /></a>
HTML
     },
    );
}

1;
