package BSE::Util::Tags;
use strict;

sub _get_parms {
  my ($acts, $args) = @_;

  my @out;
  while ($args) {
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

sub basic {
  my ($class, $acts) = @_;

  return
    (
     date =>
     sub {
       my ($func, $args) = split ' ', $_[0];
       require 'POSIX.pm';
       exists $acts->{$func}
	 or return "<:date $_[0]:>";
       my $date = $acts->{$func}->($args)
	 or return '';
       my ($year, $month, $day) = $date =~ /(\d+)\D+(\d+)\D+(\d+)/;
       $year -= 1900;
       --$month;
       return POSIX::strftime('%d-%b-%Y', 0, 0, 0, $day, $month, $year, 0, 0);
     },
     money =>
     sub {
       my ($func, $args) = split ' ', $_[0];
       exists $acts->{$func}
	 or return "** $func not found for money **";
       my $value = $acts->{$func}->($args);
       defined $value
	 or return '';
       sprintf("%.02f", $value/100.0);
     },
     script =>
     sub {
       $ENV{SCRIPT_NAME}
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

sub admin {
  my ($class, $acts, $cfg) = @_;

  return
    (
     help =>
     sub {
       my ($file, $entry) = split ' ', $_[0];

#       qq!<a href="/admin/help/$file.html#$entry" target="_blank"><img src="/images/admin/help.gif" width="16" height="16" border="0" /></a>!;
       return <<HTML;
<a href="#" onClick="window.open('/admin/help/$file.html#$entry', 'adminhelp', 'width=400,height=300,location=no,status=no,menubar=no,scrollbars=yes'); return 0;"><img src="/images/admin/help.gif" width="16" height="16" border="0" alt="help" /></a>
HTML
     },
    );
}

1;
