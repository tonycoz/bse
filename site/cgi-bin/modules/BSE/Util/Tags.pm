package BSE::Util::Tags;
use strict;
use HTML::Entities;
use DevHelp::Tags;
use DevHelp::HTML;
use vars qw(@EXPORT_OK @ISA);
@EXPORT_OK = qw(tag_error_img);
@ISA = qw(Exporter);
require Exporter;

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
       $value =~ /\d/
	 or print STDERR "Result '$value' from [$func $args] not a number\n";
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
       my @args = DevHelp::Tags->get_parms($arg, $acts, $templater);
       @args == 2
	 or die "wrong number of args (@args)";
       #print STDERR "ifEq >$left< >$right<\n";
       $args[0] eq $args[1];
     },
     ifMatch =>
     sub {
       my ($arg, $acts, $name, $templater) = @_;
       (my ($left, $right) = DevHelp::Tags->get_parms($arg, $acts, $templater)) == 2
	 or die; # leaves if in place
       $left =~ $right;
     },
     ifOr =>
     sub {
       my @args = DevHelp::Tags->get_parms(@_[0,1,3]);
       for my $item (@args) {
	 return 1 if $item;
       }
       return 0;
     },
     ifAnd =>
     sub {
       my @args = DevHelp::Tags->get_parms(@_[0,1,3]);
       for my $item (@args) {
	 return 0 unless $item;
       }
       return 1;
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
	 return escape_uri($value);
       }
       elsif ($fmt eq 'h') {
	 return escape_html($value);
       }
       return $value;
     },
    );  
}

sub tag_old {
  my ($cgi, $args, $acts, $name, $templater) = @_;

  my ($field, $func, $funcargs) = split ' ', $args;

  my $value = $cgi->param($field);
  unless (defined $value) {
    return '' unless $func && exists $acts->{$func};

    $value = $templater->perform($acts, $func, $funcargs);
  }
  defined $value or $value = '';

  escape_html($value);
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
       escape_html("@value");
     },
     old => [ \&tag_old, $cgi ],
    );
}

sub make_iterator {
  my ($class, $array, $single, $plural, $saveto) = @_;

  my $index;
  my @result =
      (
       "iterate_${plural}_reset" => sub { $index = -1 },
       $single => sub { escape_html($array->[$index]{$_[0]}) },
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
       $single => sub { escape_html($data[$index]{$_[0]}) },
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
       $single => sub { escape_html($data[$index]{$_[0]}) },
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

my %dummy_site_article =
  (
	 id=>-1,
	 parentid=>0,
	 title=>'Your site',
   );

sub tag_if_user_can {
  my ($req, $rperms, $args, $acts, $funcname, $templater) = @_;

  my @checks = split /,/, $args;
  for my $check (@checks) {
    my ($perm, $artname) = split /:/, $check, 2;
    my $article;
    if ($artname) {
      if ($artname =~ /^\[/) {
	my ($workname) = DevHelp::Tags->get_parms($artname, $acts, $templater);
	unless ($workname) {
	  print STDERR "Could not translate '$artname'\n";
	  return;
	}
	$artname = $workname;
      }
      if ($artname =~ /^(-1|\d+)$/) {
	if ($artname == -1) {
	  $article = -1;
	}
	else {
	  $article = $artname;
	}
      }
      elsif ($artname =~ /^\w+$/) {
	$article = $req->get_object($artname);
	unless ($article) {
	  if (my $artid = $req->cfg->entry('articles', $artname)) {
	    $article = $artid;
	  }
	  elsif ($acts->{$artname}) {
	    $article = $templater->perform($acts, $artname, 'id');
	  }
	  else {
	    print STDERR "Unknown article name $artname\n";
	    return;
	  }
	}
      }
    }
    else {
      $article = -1;
    }

    # whew, so we should have an article
    $req->user_can($perm, $article)
      or return;
  }

  return 1;
}

sub tag_admin_user {
  my ($req, $field) = @_;

  my $user = $req->user
    or return '';
  my $value = $user->{$field};
  defined $value or $value = '';

  return encode_entities($value);
}

sub secure {
  my ($class, $req) = @_;

  my $perms;
  return
    (
     ifUserCan => [ \&tag_if_user_can, $req, \$perms ],
     ifFormLogon => $req->session->{adminuserid},
     ifLoggedOn => [ \&tag_if_logged_on, $req ],
     adminuser => [ \&tag_admin_user, $req ],
    );
}

sub tag_error_img {
  my ($cfg, $errors, $args) = @_;

  return '' unless $errors->{$args};
  my $images_uri = $cfg->entry('uri', 'images', '/images');
  my $encoded = escape_html($errors->{$args});
  return qq!<img src="$images_uri/admin/error.gif" alt="$encoded" title="$encoded" border="0" align="top">!; 
}

1;

