package BSE::Util::Tags;
use strict;
use HTML::Entities;
use DevHelp::Tags;
use BSE::Util::HTML qw(:default escape_xml);
use vars qw(@EXPORT_OK @ISA);
@EXPORT_OK = qw(tag_error_img tag_hash tag_hash_plain tag_hash_mbcs tag_article tag_article_plain tag_object tag_object_plain);
@ISA = qw(Exporter);
require Exporter;

our $VERSION = "1.013";

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

sub bse_strftime {
  my ($cfg, $fmt, $sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst) = @_;

  require POSIX;

  my $result = 
    eval {
      require Date::Format;
      my @when = ( $sec, $min, $hour, $day, $month, $year, $wday, $wday, $isdst );
      if ($year < 7000) {
	# fix the day of week
	@when = localtime POSIX::mktime(@when);
      }
      # hack in %F support
      $fmt =~ s/(?<!%)((?:%%)*)%F/$1%Y-%m-%d/g;
      return Date::Format::strftime($fmt, \@when);
    };
  defined $result
    and return $result;

  return POSIX::strftime($fmt, $sec, $min, $hour, $day, $month, $year, $wday, $wday, $isdst);
}


sub iter_cfgsection {
  my ($cfg, $args, $acts, $tag_name, $templater) = @_;

  my $sort_filter = '';
  if ($args =~ s/((?:sort|filter)=.*)//s) {
    $sort_filter = $1;
  }

  my ($section) = DevHelp::Tags->get_parms($args, $acts, $templater)
    or return;

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

  return BSE::Sort::bse_sort(\%types, $sort_filter, @entries);
}

sub tag_adminbase {
  my ($cfg, $arg) = @_;

  require BSE::CfgInfo;
  return escape_html(BSE::CfgInfo::admin_base_url($cfg));
}

sub tag_adminurl {
  my ($cfg, $args, $acts, $tag_name, $templater) = @_;

  my ($script, %params) = DevHelp::Tags->get_parms($args, $acts, $templater);

  return escape_html($cfg->admin_url($script, \%params));
}

sub static {
  my ($class, $acts, $cfg) = @_;

  my $static_ajax = $cfg->entry('basic', 'staticajax', 0);
  require BSE::Util::Iterate;
  my $it = BSE::Util::Iterate->new;
  return
    (
     date =>
     sub {
       my ($arg, $acts, $name, $templater) = @_;
       my ($quote, $fmt, $func, $args) = 
	 $arg =~ m/(?:([\"\'])([^\"\']+)\1\s+)?(\S+)(?:\s+(\S+.*))?/;
       $fmt = "%d-%b-%Y" unless defined $fmt;
       exists $acts->{$func}
	 or return "<:date $_[0]:>";
       my $date = $templater->perform($acts, $func, $args)
	 or return '';
       my ($year, $month, $day, $hour, $min, $sec) = 
	 $date =~ /(\d+)\D+(\d+)\D+(\d+)(?:\D+(\d+)\D+(\d+)\D+(\d+))?/;
       $hour = $min = $sec = 0 unless defined $sec;
       $year -= 1900;
       --$month;
       # passing the isdst as 0 seems to provide a more accurate result than
       # -1 on glibc.
       return bse_strftime($cfg, $fmt, $sec, $min, $hour, $day, $month, $year, -1, -1, -1);
     },
     today => [ \&tag_today, $cfg ],
     money =>
     sub {
       my ($arg, $acts, $name, $templater) = @_;
       my ($func, $args) = split ' ', $arg, 2;
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
     number => \&tag_number,
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
       return $gen->format_body(acts => $acts, 
				articles => 'Articles', 
				text => $value, 
				templater => $templater);
     },
     nobodytext => [\&tag_nobodytext, $cfg ],
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
     concatenate => \&tag_concatenate,
     cat => \&tag_concatenate,
     arithmetic => \&tag_arithmetic,
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
       $out = lc $out; # start all lowercase
       $out =~ s/(^\'?|\W\'|[^'\w])(\w)/$1\U$2/g;
       $out;
     },
     adminbase => [ \&tag_adminbase, $cfg ],
     adminurl => [ \&tag_adminurl, $cfg ],
     help => [ \&tag_help, $cfg, 'user' ],
     $it->make_iterator(\&DevHelp::Tags::iter_get_repeat, 'strepeat', 'strepeats'),
     report => [ \&tag_report, $cfg ],
     
     # the following is so you can embed a report in another report, since
     # report conflicts with a tag name used within reports
     subreport => [ \&tag_report, $cfg ],

     cond => \&tag_cond,

     target => \&tag_target,

     (
      $static_ajax 
      ? (
	 ajax => [ \&tag_ajax, $cfg ],
	 ifAjax => 1,
	)
      : (
	 ajax => '',
	 ifAjax => 0,
	)
      ),

     _format => 
     sub {
       my ($value, $fmt) = @_;
       if ($fmt eq 'u') {
	 return escape_uri($value);
       }
       elsif ($fmt eq 'U') {
	 return escape_uri(unescape_html($value));
       }
       elsif ($fmt eq 'h') {
	 return escape_html($value);
       }
       elsif ($fmt eq 'x') {
	 return escape_xml(unescape_html($value));
       }
       elsif ($fmt eq 'z') {
	 return unescape_html($value);
       }
       elsif ($fmt eq 'c') {
	 my $workset = $cfg->entry('html', 'charset', 'iso-8859-1');
	 require Encode;
	 my $work = unescape_html($value);
	 Encode::from_to($work, 'utf8', $workset);
	 return $work;
       }
       elsif ($fmt =~ /%/) {
	 return sprintf($fmt, $value);
       }
       return $value;
     },
    );  
}

sub tag_arithmetic {
  my ($arg, $acts, $name, $templater) = @_;

  my $prefix;

  if ($arg =~ s/^\s*([^:\s]*)://) {
    $prefix = $1;
  }
  else {
    $prefix = '';
  }
  
  my $not_found;
  $arg =~ s/(\[\s*([^\W\d]\w*)(\s+\S[^\[\]]*)?\s*\])/
    exists $acts->{$2} ? $templater->perform($acts, $2, $3) 
      : (++$not_found, $1)/ge;

  if ($not_found) {
    die "ENOIMPL\n";
  }

  # this may be made more restrictive
  my $result = eval $arg;

  if ($@) {
    print STDERR "code generated by arithmetic: >>$arg<<\n";
    return escape_html("** arithmetic error ".$@." **");
  }

  if ($prefix eq 'i') {
    $result = int($result);
  }
  elsif ($prefix eq 'r') {
    $result = sprintf("%.0f", $result);
  }
  elsif ($prefix =~ /^d(\d+)$/) {
    $result = sprintf("%.*f", $1, $result);
  }

  return escape_html($result);
}

sub tag_nobodytext {
  my ($cfg, $arg, $acts, $name, $templater) = @_;
  my ($func, $args) = split ' ', $arg, 2;
  
  $args = '' unless defined $args;
  exists $acts->{$func}
    or return "<: nobodytext $func $args :>";
  my $value = $templater->perform($acts, $func, $args);
  defined $value
    or return '';
  
  $value = decode_entities($value);
  
  require Generate;
  my $gen = Generate->new(cfg=>$cfg);
  $gen->remove_block('Articles', $acts, \$value);
  
  return escape_html($value);
}

sub tag_old {
  my ($cgi, $args, $acts, $name, $templater) = @_;

  my ($field, $func, $funcargs);
  
  if ($args =~ /^(\[[^\[\]]*(?:\[[^\[\]]*\][^\[\]]*)*\])(.*)/) {
    my ($fieldargs, $rest) = ($1, $2);
    ($field) = DevHelp::Tags->get_parms($fieldargs, $acts, $templater);
    defined $rest or $rest = '';
    ($func, $funcargs) = split ' ', $rest, 2;
  }
  else {
    ($field, $func, $funcargs) = split ' ', $args, 3;
  }

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

=item basic dynamic tags

Tags available for all dynamic pages, user and admin alike.

Includes the basic static tags.

=cut

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
     lcgi => [ tag_lcgi => $class, $cgi ],
     deltag => [ tag_deltag => $class ],
     ifTagIn => [ tag_ifTagIn => $class ],
     old => [ \&tag_old, $cgi ],
     oldi => [ \&tag_oldi, $cgi ],
     $it->make_iterator(\&DevHelp::Tags::iter_get_repeat, 'repeat', 'repeats'),
     dynreplace => \&tag_replace,
     dyntoday => [ \&tag_today, $cfg ],
     dynreport => [ \&tag_report, $cfg ],
     ajax => [ \&tag_ajax_dynamic, $cfg ],
     ifAjax => [ \&tag_ifAjax, $cfg ],
     $it->make_iterator([ \&iter_cfgsection, $cfg ], 'dyncfgentry', 'dyncfgsection'),
    );
}

sub tag_lcgi {
  my ($self, $cgi, $args) = @_;

  $cgi or return '';
  my $sep = "/";
  if ($args =~ s/^\"([^\"\w]+)\"\s+//) {
    $sep = $1;
  }

  return escape_html(join $sep, $cgi->param($args));
}

sub tag_deltag {
  my ($self, $args, $acts, $func, $templater) = @_;

  my $sep = "/";
  if ($args =~ s/^\"([^\"\w]+)\"\s+//) {
    $sep = $1;
  }

  require BSE::TB::Tags;
  my ($del, @tags) = $templater->get_parms($args, $acts);
  my $error;
  my %del = map { BSE::TB::Tags->canon_name($_, \$error) => 1 }
    split /\Q$sep/, $del;

  return join $sep,
    grep !$del{lc $_},
      map BSE::TB::Tags->name($_, \$error),
	map { split /\Q$sep/ }
	  @tags;
}

sub tag_ifTagIn {
  my ($self, $args, $acts, $func, $templater) = @_;

  my $sep = "/";
  if ($args =~ s/^\"([^\"\w]+)\"\s+//) {
    $sep = $1;
  }

  require BSE::TB::Tags;
  my $error;
  my ($check, @tags) = $templater->get_parms($args, $acts);
  @tags = map BSE::TB::Tags->name($_, \$error),
    map { split /\Q$sep/ }
      @tags;

  $check = BSE::TB::Tags->canon_name($check, \$error)
    or return 0;

  for my $tag (@tags) {
    if (lc $tag eq $check) {
      return 1;
    }
  }

  return 0;
}

sub common {
  my ($class, $req) = @_;

  return
    (
     BSE::Util::Tags->basic(undef, $req->cgi, $req->cfg),
     csrfp => [ \&tag_csrfp, $req ],
     ifError => 0, # overridden elsewhere
    );
}

=item tag csrfp

Generate a token that can be used to prevent cross-site request
forgery.

Takes a single argument, the action to be authenticated.

=cut

sub tag_csrfp {
  my ($req, $args) = @_;

  $args
    or return "** missing required argument **";

  my ($name, $type) = split ' ', $args;
  defined $type
    or $type = 'plain';

  my $token = $req->get_csrf_token($name);

  $type eq "plain" and return $token;
  $type eq "hidden" and return
    qq(<input type="hidden" name="_csrfp" value="$token" />);
  return "** unknown csrfp type $type **";
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
  my ($class, $acts, $cfg, $req) = @_;

  my $oit = BSE::Util::Iterate::Objects->new(cfg => $cfg);
  return
    (
     help => [ \&tag_help, $cfg, 'admin' ],
     $oit->make
     (
      single => "auditentry",
      plural => "auditlog",
      code => [ iter_auditlog => $class, $req ],
     ),
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

sub iter_auditlog {
  my ($class, $req, $args, $acts, $funcname, $templater) = @_;

  my (@args) = DevHelp::Tags->get_parms($args, $acts, $templater);
  require BSE::TB::AuditLog;
  return sort { $b->id <=> $a->id }
    BSE::TB::AuditLog->getBy(@args);
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

  my $debug = $req->cfg->entry('debug', 'ifUserCan', 0);
  $debug 
    and print STDERR "Handling ifUserCan $args:\n";
  my @checks = split /,/, $args;
  for my $check (@checks) {
    my ($perm, $artname) = split /:/, $check, 2;
    $debug 
      and print STDERR "  Perm: '$perm'\n";
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
	    #print STDERR "Unknown article name $artname\n";
	    die "ENOIMPL: Unknown article name\n";
	  }
	}
      }
    }
    else {
      $article = -1;
    }

    # whew, so we should have an article
    $req->user_can($perm, $article)
      or return 0;
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
     csrfp => [ \&tag_csrfp, $req ],
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
  my $image = $cfg->entry('error_img', 'image', "$images_uri/admin/error.gif");
  my $width = $cfg->entry('error_img', 'width', 16);
  my $height = $cfg->entry('error_img', 'height', 16);
  my $encoded = escape_html($msg);
  return qq!<img src="$image" alt="$encoded" title="$encoded" width="$width" height="$height" border="0" align="top" />!; 
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
	  $tmp =~ s/\$([1-9\$])/
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
	  $tmp =~ s/\$([1-9\$])/
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
  if ($value =~ /\cJ/ && $value =~ /\cM/) {
    $value =~ tr/\cM//d;
  }

  escape_html($value);
}

sub tag_hash_mbcs {
  my ($object, $args) = @_;

  my $value = $object->{$args};
  defined $value or $value = '';
  if ($value =~ /\cJ/ && $value =~ /\cM/) {
    $value =~ tr/\cM//d;
  }
  escape_html($value, '<>&"');
}

sub tag_hash_plain {
  my ($hash, $args) = @_;

  my $value = $hash->{$args};
  defined $value or $value = '';

  $value;
}

my %bad_methods = map { $_ => 1 } qw(remove new add save);

sub tag_object {
  my ($object, $args, $acts, $func) = @_;

  $object or return '';

  $bad_methods{$args}
    and return "** $args method not available **";

  $object->can($args)
    or return "** $func has no method $args **";

  my $value = $object->$args();
  defined $value or return "";

  return escape_html($value);
}

sub tag_object_plain {
  my ($object, $args, $acts, $func) = @_;

  $object or return '';

  $bad_methods{$args}
    and return "** $args method not available **";

  $object->can($args)
    or return "** $func has no method $args **";

  my $value = $object->$args();
  defined $value or return "";

  return $value;
}

sub tag_today {
  my ($cfg, $args) = @_;

  $args =~ s/^"(.+)"$/$1/;

  $args ||= "%d-%b-%Y";

  return bse_strftime($cfg, $args, localtime);
}

sub tag_report {
  my ($cfg, $args, $acts, $tag_name, $templater) = @_;

  my ($rep_name, $template, @args) = 
    DevHelp::Tags->get_parms($args, $acts, $templater);
  defined $rep_name
    or return "** no report name supplied to $tag_name tag **";

  require BSE::Report;
  my $reports = BSE::Report->new($cfg);
  my $report = $reports->load($rep_name, undef, BSE::DB->single);
  $report
    or return "** could not load report '$rep_name' **";

  # this will get embedded and normal tag replacement will then
  # operate on it, no need to include basic/static tags
  my %acts;
  my $msg;
  %acts =
    (
     %$acts,
     $reports->show_tags($rep_name, BSE::DB->single, \$msg, @args),
    );

  $msg
    and return "** error in $tag_name: $msg **";

  if (!defined $template or $template eq '-') {
    $template = $reports->show_template($rep_name) || 'admin/reports/show1';
  }

  my $html = BSE::Template->get_source($template, $cfg);
  if ($html =~ /<:\s*embed\s*start\s*:>(.*)<:\s*embed\s*end\s*:>/s
     || $html =~ m"<\s*body[^>]*>(.*)<\s*/\s*body>"s) {
    $html = $1;
  }

  return BSE::Template->replace($html, $cfg, \%acts);
}

sub _if_ajax {
  my ($cfg) = @_;

  return
    unless $cfg->entry('basic', 'ajax', 0);

  return 1
    if $cfg->entry('basic', 'allajax', 0);

  my $ua = $ENV{HTTP_USER_AGENT};
  defined $ua or $ua = ''; # some clients don\'t send a UA # silly cperl

  my %fail_entries = $cfg->entries('nonajax user agents');
  for my $re (values %fail_entries) {
    return
      if $ua =~ /$re/;
  }

  my %entries = $cfg->entries('ajax user agents');
  for my $re (values %entries) {
    return 1
      if $ua =~ /$re/;
  }

  return;
}

sub tag_ifAjax {
  my ($cfg) = @_;

  return _if_ajax($cfg) ? 1 : 0;
}

sub tag_ajax_dynamic {
  my ($cfg, $args, $acts, $tag_name, $templater) = @_;

  return '' unless _if_ajax($cfg);

  return tag_ajax($cfg, $args, $acts, $tag_name, $templater);
}

sub tag_ajax {
  my ($cfg, $args, $acts, $tag_name, $templater) = @_;

  my ($name, $arg_rest) = split ' ', $args, 2;
 
  my $defn = $cfg->entry('ajax definitions', $name)
    or return "** unknown ajax definition $name **";
  my ($type, $rest) = split ':', $defn, 2;

  defined $arg_rest or $arg_rest = '';

  if ($type eq 'inline') {
    # just replace $1, $2, etc in the rest of the text
    my @args = DevHelp::Tags->get_parms($arg_rest, $acts, $templater);
    my $macro = $rest;
    eval {
      $macro =~ s/(\$([1-9\$]))/
	$2 eq '$' ? '$' : $2 <= @args 
         ? die "** not enough parameters for ajax definition $name **\n" : $args[$1-1]/xge;
    };
    $@ and return $@;

    return $macro;
  }
  else {
    return "** invalid type $type for ajax definition $name **";
  }
}

sub tag_article {
  my ($article, $cfg, $args) = @_;

  return escape_html(tag_article_plain($article, $cfg, $args));
}

sub tag_article_plain {
  my ($article, $cfg, $args) = @_;

  my $value;
  if ($args eq 'link'
     && ref($article) ne 'HASH') {
    $value = $article->link($cfg);
  }
  else {
    $value = $article->{$args};
    defined $value or $value = '';
    if ($value =~ /\cJ/ && $value =~ /\cM/) {
      $value =~ tr/\cM//d;
    }
  }

  return $value;
}

=item tag cond

Usage:

  cond test truevalue falsevalue

Does [] replacement, if test is a true value, returns I<truevalue>,
otherwise returns I<falsevalue>.

eg.

  <:wrap foo.tmpl title => [cond [ifNew] "Create" "Edit" ] :>

=cut

sub tag_cond {
  my ($args, $acts, $tagname, $templater) = @_;

  my ($cond, $true, $false) = 
    DevHelp::Tags->get_parms($args, $acts, $templater);

  defined $true or $true = "";
  defined $false or $false = "";

  return $cond ? $true : $false;
}

=item tag target

Usage:

=over

target I<script> I<target> I<parameters>...

=back

Does [] replacement, returns a url as with dyntarget.

eg.

  <:target user orderdetaila id [order randomId]:>

=cut

sub tag_target {
  my ($args, $acts, $tagname, $templater) = @_;

  my ($script, $target, @opts) =
    DevHelp::Tags->get_parms($args, $acts, $templater);

  return BSE::Cfg->single->user_url($script, $target, @opts);
}

=item tag concatenate

=item tag cat

Usage:

  concatenate args...
  cat args...

Returns the concatenation of the supplied strings.

Does [] replacement.

eg.

  <:cfg [cat "myprefix " [cgi foo]] key "":>

=cut

sub tag_concatenate {
  my ($arg, $acts, $name, $templater) = @_;

  my @items = DevHelp::Tags->get_parms($arg, $acts, $templater);

  return join '', @items;
}

sub tag_number {
  my ($args, $acts, $tagname, $templater) = @_;

  my ($format, $value) = 
    DevHelp::Tags->get_parms($args, $acts, $templater);
  $format or return "* no number format *";
  my $section = "number $format";
  my $cfg = BSE::Cfg->single;
  my $comma_sep = $cfg->entry($section, "comma", ",");
  $comma_sep =~ s/^"(.*)"$/$1/;
  $comma_sep =~ /\w/ and return "* comma cannot be a word character *";
  my $comma_limit = $cfg->entry($section, "comma_limit", 1000);
  my $commify = $cfg->entry($section, "commify", 1);
  my $dec_sep = $cfg->entry($section, "decimal", ".");
  my $div = $cfg->entry($section, "divisor", 1)
    or return "* divisor must be non-zero *";
  my $places = $cfg->entry($section, "places", -1);

  my $div_value = $value / $div;
  my $formatted = $places < 0 ? $div_value : sprintf("%.*f", $places, $div_value);

  my ($int, $frac) = split /\./, $formatted;
  if ($commify && $int >= $comma_limit) {
    1 while $int =~ s/([0-9])([0-9][0-9][0-9]\b)/$1$comma_sep$2/;
  }

  if (defined $frac) {
    return $int . $dec_sep . $frac;
  }
  else {
    return $int;
  }
}

=item mail_tags()

Return base tags suitable for email templates.

Currently returns the basic static tags.

=cut

sub mail_tags {
  my ($class) = @_;

  return 
    (
     $class->static(undef, BSE::Cfg->single),
     _format =>
     sub {
       my ($value, $fmt) = @_;
       if ($fmt =~ /^m(\d+)/) {
	 return sprintf("%$1s", sprintf("%.2f", $value/100));
       }
       elsif ($fmt =~ /%/) {
	 return sprintf($fmt, $value);
       }
       elsif ($fmt =~ /^\d+$/) {
	 return substr($value . (" " x $fmt), 0, $fmt);
       }
       elsif ($fmt eq "h") {
	 return escape_html($value);
       }
       elsif ($fmt eq "u") {
	 return escape_uri($value);
       }
       else {
	 return $value;
       }
     },
     with_wrap => \&tag_with_wrap,
    );
}

sub tag_with_wrap {
  my ($args, $text) = @_;

  my $margin = $args =~ /^\d+$/ && $args > 30 ? $args : 70;

  require Text::Wrap;
  # do it twice to prevent a warning
  $Text::Wrap::columns = $margin;
  $Text::Wrap::columns = $margin;

  return Text::Wrap::fill('', '', split /\n/, $text);
}

1;

