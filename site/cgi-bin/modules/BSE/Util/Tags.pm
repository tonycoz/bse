package BSE::Util::Tags;
use strict;
use HTML::Entities;
use DevHelp::Tags;
use DevHelp::HTML;
use vars qw(@EXPORT_OK @ISA);
@EXPORT_OK = qw(tag_error_img tag_hash tag_hash_plain);
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

sub iter_cfgsection {
  my ($cfg, $args) = @_;

  $args =~ s/^\s*\"([^\"]+)\"\s*//
    or return;
  my $section = $1;

  my %entries = $cfg->entries($section);
  my @entries = map +{ key => $_, value => $entries{$_} }, keys %entries;

  my %types;

  # guess types
  unless (grep /\D/, keys %entries) {
    $types{key} = 'n';
  }
  unless (grep /\D/, values %entries) {
    $types{value} = 'n';
  }

  require BSE::Sort;

  return BSE::Sort::bse_sort(\%types, $args, @entries);
}

sub tag_adminbase {
  my ($cfg, $arg) = @_;

  require BSE::CfgInfo;
  return escape_html(BSE::CfgInfo::admin_base_url($cfg));
}

sub static {
  my ($class, $acts, $cfg) = @_;

  require BSE::Util::Iterate;
  my $it = BSE::Util::Iterate->new;
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
       #$value =~ /\d/
       #  or print STDERR "Result '$value' from [$func $args] not a number\n";
       $value =~ /\d/ or $value = 0;
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
       require Generate;
       my $gen = Generate->new(cfg=>$cfg);
       return $gen->format_body($acts, 'Articles', $value, 'tr',
				1, 0);
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
       my ($args, $acts, $myfunc, $templater) = @_;
       my ($section, $key, $def) = 
	 DevHelp::Tags->get_parms($args, $acts, $templater);
       $cfg or return '';
       defined $def or $def = '';
       $cfg->entry($section, $key, $def);
     },
     $it->make_iterator([ \&iter_cfgsection, $cfg ], 'cfgentry', 'cfgsection'),
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
     add =>
     sub {
       my ($arg, $acts, $name, $templater) = @_;
       my @items = DevHelp::Tags->get_parms($arg, $acts, $templater);
       my $sum = 0;
       $sum += $_ for @items;
       $sum;
     },
     concatenate =>
     sub {
       my ($arg, $acts, $name, $templater) = @_;
       my @items = DevHelp::Tags->get_parms($arg, $acts, $templater);
       join '', @items;
     },
     match =>
     sub {
       my ($arg, $acts, $name, $templater) = @_;
       my ($str, $re, $out, $def)
	 = DevHelp::Tags->get_parms($arg, $acts, $templater);
       $re or return '** no regexp supplied to match **';
       $out or $out = '$1';
       defined $def or $def = '';
       my @matches = $str =~ /$re/
	 or return $def;
       defined or $_ = '' for @matches;

       $out =~ s/\$([1-9\$])/
	 $1 eq '$' ? '$' : $1 <= @matches ? $matches[$1-1] : '' /ge;

       $out;
     },
     replace => \&tag_replace,
     lc =>
     sub {
       my ($arg, $acts, $name, $templater) = @_;
       my @items = DevHelp::Tags->get_parms($arg, $acts, $templater);
       lc join '', @items;
     },
     uc =>
     sub {
       my ($arg, $acts, $name, $templater) = @_;
       my @items = DevHelp::Tags->get_parms($arg, $acts, $templater);
       uc join '', @items;
     },
     lcfirst =>
     sub {
       my ($arg, $acts, $name, $templater) = @_;
       my @items = DevHelp::Tags->get_parms($arg, $acts, $templater);
       lcfirst join '', @items;
     },
     ucfirst =>
     sub {
       my ($arg, $acts, $name, $templater) = @_;
       my @items = DevHelp::Tags->get_parms($arg, $acts, $templater);
       ucfirst join '', @items;
     },
     capitalize =>
     sub {
       my ($arg, $acts, $name, $templater) = @_;
       my @items = DevHelp::Tags->get_parms($arg, $acts, $templater);
       my $out = join '', @items;
       $out =~ s/\b(\w)/\U$1/g;
       $out;
     },
     adminbase => [ \&tag_adminbase, $cfg ],
     help => [ \&tag_help, $cfg, 'admin' ],
     
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

  my ($field, $func, $funcargs) = split ' ', $args, 3;

  my $value = $cgi->param($field);
  if (defined $value) {
    return escape_html($value);
  }

  return '' unless $func && exists $acts->{$func};

  $value = $templater->perform($acts, $func, $funcargs);
  defined $value or $value = '';

  return $value;
}

sub tag_oldi {
  my ($cgi, $args, $acts, $name, $templater) = @_;

  my ($field, $num, $func, @funcargs) = 
    DevHelp::Tags->get_parms($args, $acts, $templater);

  my @values = $cgi->param($field);
  if (@values && $num < @values) {
    return escape_html($values[$num]);
  }

  return '' unless $func && exists $acts->{$func};

  my $value = $templater->perform($acts, $func, "@funcargs");
  defined $value or $value = '';

  return $value;
}

sub basic {
  my ($class, $acts, $cgi, $cfg) = @_;

  require BSE::Util::Iterate;
  my $it = BSE::Util::Iterate->new;
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
     oldi => [ \&tag_oldi, $cgi ],
     $it->make_iterator(\&DevHelp::Tags::iter_get_repeat, 'repeat', 'repeats'),
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
     help => [ \&tag_help, $cfg, 'admin' ],
    );
}

my %help_styles =
  (
   admin => { 
	     template => 'admin/helpicon',
	     prefix => '/admin/help/',
	    },
   user => {
	    template => 'helpicon',
	    prefix => '/help/',
	   },
  );

sub tag_stylecfg {
  my ($cfg, $style, $args) = @_;

  my ($name, $default) = split ' ', $args, 2;

  return $cfg->entry("help style $style", $name, $default);
}

sub tag_help {
  my ($cfg, $defstyle, $args) = @_;

  my ($file, $entry, $style) = split ' ', $args;

  $style ||= $defstyle;

  my $template = $cfg->entry("help style $style", 'template')
    || $cfg->entry("help style $defstyle", 'template')
    || $help_styles{$style}{template}
    || $help_styles{$defstyle}{template};
  my $prefix = $cfg->entry("help style $style", 'prefix')
    || $cfg->entry("help style $defstyle", 'prefix')
    || $help_styles{$defstyle}{prefix}
    || $help_styles{$defstyle}{prefix};
  require BSE::Template;
  my %acts=
    (
     prefix => $prefix,
     file => $file,
     entry => $entry,
     stylename => $style,
     stylecfg => [ \&tag_stylecfg, $cfg, $style ],
    );

  return BSE::Template->get_page($template, $cfg, \%acts,
				 $help_styles{$defstyle}{template});
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
  my ($cfg, $errors, $args, $acts, $func, $templater) = @_;

  my ($arg, $num) = DevHelp::Tags->get_parms($args, $acts, $templater);
  #print STDERR "name $arg num $num\n";
  return '' unless $errors->{$arg};
  my $msg = $errors->{$arg};
  if (ref $errors->{$arg}) {
    my @errors = @$msg;
    return '' unless @$msg > $num && $msg->[$num];
    $msg = $msg->[$num];
  }
  my $images_uri = $cfg->entry('uri', 'images', '/images');
  my $encoded = escape_html($msg);
  return qq!<img src="$images_uri/admin/error.gif" alt="$encoded" title="$encoded" border="0" align="top" />!; 
}

sub tag_replace {
  my ($arg, $acts, $name, $templater) = @_;
  my ($str, $re, $with, $global)
    = DevHelp::Tags->get_parms($arg, $acts, $templater);
  $re or return '** no regexp supplied to match **';
  defined $with or $with = '$1';
  if ($global) {
    $str =~ s{$re}
      {
	# yes, this sucks
	my @out = ($1, $2, $3, $4, $5, $6, $7, $8, $9);
	defined or $_ = '' for @out;
	my $tmp = $with;
	{
	  $tmp =~ s/\$([1-9\$])/$1 eq '$' ? '$' :
	    $1 eq '$' ? '$' : $out[$1-1] /ge;
	}
	$tmp;
      }ge;
  }
  else {
    $str =~ s{$re}
      {
	# yes, this sucks
	my @out = ($1, $2, $3, $4, $5, $6, $7, $8, $9);
	defined or $_ = '' for @out;
	my $tmp = $with;
	{
	  $tmp =~ s/\$([1-9\$])/$1 eq '$' ? '$' :
	    $1 eq '$' ? '$' : $out[$1-1] /ge;
	}
	$tmp;
      }e;
  }
    
  $str;
}

sub tag_hash {
  my ($hash, $args) = @_;

  my $value = $hash->{$args};
  defined $value or $value = '';

  escape_html($value);
}

sub tag_hash_plain {
  my ($hash, $args) = @_;

  my $value = $hash->{$args};
  defined $value or $value = '';

  $value;
}

1;

