package DevHelp::Validate;
use strict;
require Exporter;
use vars qw(@EXPORT_OK @ISA);
@EXPORT_OK = qw(dh_validate dh_validate_hash dh_fieldnames dh_configure_fields);
@ISA = qw(Exporter);
use Carp qw(confess);

our $VERSION = "1.009";

my $re_real =
  qr/
      (
	[-+]?   # optional sign
	(?:
	  [0-9]+(?:\.[0-9]*)?   # either 9 with optional decimal digits
	  |
	  \.[0-9]+         # or . with required digits
	)
	(?:[eE][-+]?[0-9]+)?  # optional exponent
      )
    /x;

my %built_ins =
  (
   email => 
   {
    match => qr/^[^\s\@][^\@]*\@[\w.-]+\.\w+$/,
    error => '$n is not a valid email address',
   },
   phone => 
   {
    match => qr/\d(?:\D*\d){3}/,
    error => '$n is not a valid phone number',
   },
   postcode => 
   {
    match => qr/\d(?:\D*\d){3}/,
    error => '$n is not a valid post code',
   },
   # international post code
   dh_int_postcode =>
   {
    match => qr/[\w-](?:[^\w-]*[\w-]){3}/,
    error => '$n is not a valid post code',
   },
   url =>
   {
    match => qr!^\w+://[\w-]+(?:\.[\w-]+)+(?::\d+)?!,
    error => '$n is not a valid URL',
   },
   weburl =>
   {
    match => qr!^https?://[\w-]+(?:\.[\w-]+)+(?::\d+)?!,
    error => '$n is not a valid URL, it must start with http:// or https://',
   },
   newbieweburl =>
   {
    match => qr!^(?:https?://)?[\w-]+(?:\.[\w-]+)+(?::\d+)?!,
    error => '$n is not a valid URL',
   },
   confirm =>
   {
    confirm=>'password',
   },
   newconfirm =>
   {
    newconfirm=>'password',
   },
   required =>
   {
    required => 1,
   },
   abn => 
   {
    match => qr/\d(?:\D*\d){7}/,
    error => '$n is not a valid ABN',
   },
   creditcardnumber =>
   {
    match => qr/^\D*\d(?:\D*\d){11,15}\D*$/,
    error => '$n is not a valid credit card number',
   },
   creditcardexpiry =>
   {
    ccexpiry => 1,
   },
   creditcardexpirysingle =>
   {
    ccexpirysingle => 1,
   },
   creditcardcvv =>
   {
    match => qr/^(\d){3,4}$/,
    error => '$n is the 3 or 4 digit code on the back of your card',
   },
   miaa =>
   {
    match => qr/^\s*\d{1,6}\s*$/,
    error => 'Not a valid MIAA membership number',
   },
   decimal =>
   {
    match => qr/^\s*(?:\d+(?:\.\d*)?|\.\d+)\s*$/,
    error => 'Not a valid number',
   },
   money =>
   {
    match => qr/^\s*(?:\d+(?:\.\d\d)?|\.\d\d)\s*$/,
    error => 'Not a valid money amount',
   },
   date =>
   {
    date => 1,
   },
   birthdate =>
   {
    date => 1,
    maxdate => '+0y',
    maxdatemsg => 'Your $n must be in the past',
   },
   adultbirthdate =>
   {
    date => 1,
    maxdate => '-10y',
    maxdatemsg => 'You must be at least 10 years old...',
    mindate => '-100y',
   },
   futuredate =>
   {
    date => 1,
    mindate => '-1d',
    mindatemsg => 'The date entered must be in the future',
   },
   pastdate => 
   {
    date => 1,
    maxdate => '+1d',
    maxdatemsg => 'The date entered must be in the past',
   },
   time =>
   {
    time => 1,
   },
   integer =>
   {
    integer => 1,
   },
   natural => 
   {
    integer => '0-', # 0 or higher
   },
   positiveint =>
   {
    integer => '1-', # 1 or higher
   },
   dh_one_line => 
   {
    nomatch => qr/[\x0D\x0A]/,
    error => '$n may only contain a single line',
   },
   real =>
   {
    real => 1,
   },
   time =>
   {
    # we accept 24-hour time, or 12 hour with (a|p|am|pm)
    match => qr!^(?:                   # first 24 hour time:
                   (?:[01]?\d|2[0-3])  # hour 0-23
                      [:.]             # separator
                      [0-5]\d          # minute
                      (?:[:.][0-5]\d)? # optional seconds
                  |                    # or 12 hour time:
		    (?:0?[1-9]|1[012]) # hour 1-12
		     (?:[:.]           # optionally separator followed
		      [0-5]\d          # by minutes
                      (?:[:.][0-5]\d)? # optionall by seconds
                    )? 
		    [ap]m?             # followed by afternoon/morning
                  )$!ix,
    error=>'Invalid time $n',
   },
  );

sub new {
  my ($class, %opts) = @_;

  my $self = bless \%opts, $class;

  # configure validation
  my $fields = $self->{fields};
  my $rules = $self->{rules} || {};

  my %cfg_rules;
  _get_cfg_fields(\%cfg_rules, $self->{cfg}, $self->{section}, $fields, $opts{dbh})
    if $self->{cfg} && $self->{section};

  for my $rulename (keys %$rules) {
    unless (exists $cfg_rules{rules}{$rulename}) {
      $cfg_rules{rules}{$rulename} = $rules->{$rulename};
    }
  }
  for my $rulename (keys %built_ins) {
    unless (exists $cfg_rules{rules}{$rulename}) {
      $cfg_rules{rules}{$rulename} = $built_ins{$rulename};
    }
  }

  # merge the supplied fields into the config fields
  my $cfg_fields = $cfg_rules{fields};
  for my $field ( keys %$fields ) {
    my $src = $fields->{$field};

    my $dest = $cfg_fields->{$field} || {};

    # the config overrides the software supplied fields
    for my $override (qw(description required required_error maxlength range_error mindatemsg maxdatemsg ne_error)) {
      if (defined $src->{$override} && !defined $dest->{$override}) {
	$dest->{$override} = $src->{$override};
      }
    }

    # but we add rules and required_if
    if ($dest->{rules}) {
      my $rules = $src->{rules};

      # make a copy of the rules array if it's supplied that way so
      # we don't modify someone else's data
      $rules = ref $rules ? [ @$rules ] : [ split /;/, $rules ];

      push @$rules, split /;/, $dest->{rules};

      $dest->{rules} = $rules;
    }
    elsif ($src->{rules}) {
      $dest->{rules} = $src->{rules};
    }
    if ($dest->{required_if}) {
      $dest->{required_if} .= ";" . $src->{required_if} if $src->{required_if};
    }
    elsif ($src->{required_if}) {
      $dest->{required_if} = $src->{required_if};
    }

    $cfg_fields->{$field} = $dest if keys %$dest;
  }

  $self->{cfg_fields} = $cfg_fields;
  $self->{cfg_rules} = $cfg_rules{rules};

  return $self;
}

sub dh_validate {
  my ($cgi, $errors, $validation, $cfg, $section) = @_;

  return DevHelp::Validate::CGI->new
    (
     cfg => $cfg,
     section => $section, 
     fields => $validation->{fields}, 
     rules => $validation->{rules}, 
     optional => $validation->{optional}, 
     dbh => $validation->{dbh},
    )
    ->validate($cgi, $errors);
}

sub dh_validate_hash {
  my ($hash, $errors, $validation, $cfg, $section) = @_;

  return DevHelp::Validate::Hash->new
    (
     cfg => $cfg,
     section => $section,
     fields => $validation->{fields}, 
     rules => $validation->{rules}, 
     optional=>$validation->{optional},
     dbh => $validation->{dbh},
    )
    ->validate($hash, $errors);
}

sub _validate {
  my ($self, $errors) = @_;

  my $cfg_fields = $self->{cfg_fields};
  my $cfg_rules = $self->{cfg_rules};
  my $optional = $self->{optional};
  
  for my $field ( keys %$cfg_fields ) {
    $self->validate_field($field, $cfg_fields->{$field}, $cfg_rules, 
			  $optional, $errors);
  }
  
  !keys %$errors;
}

my @dow_tokens = qw(sun mon tue wed thu fri sat);
my @dow_names = qw(Sunday Monday Tuesday Wednesday Thursday Friday Saturday);
my %dow_trans;
@dow_trans{@dow_tokens} = @dow_names;

sub validate_field {
  my ($self, $field, $info, $rules, $optional, $errors) = @_;

  my @data = $self->param($field);

  my $required = $info->{required};
  if (@data && $data[0] !~ /\S/ && $info->{required_if}) {
    # field is required if any of the named fields are non-blank
    for my $testfield (split /;/, $info->{required_if}) {
      my ($field_name, $field_value) = split /=/, $testfield;
      my $testvalue = $self->param($field_name);
      if (defined $testvalue &&
	  (defined $field_value && $testvalue eq $field_value
	   || !defined $field_value && $testvalue =~ /\S/)) {
	++$required;
	last;
      }
    }
  }

  if (defined $info->{maxlength}) {
    for my $testdata (@data) {
      if (length $testdata > $info->{maxlength}) {
	$errors->{$field} = _make_error($field, $info, {},
					q!$n too long!);
	return;
      }
    }
  }

  my $rule_names = $info->{rules};
  defined $rule_names or $rule_names = '';
  $rule_names = [ split /;/, $rule_names ] unless ref $rule_names;
  
  push @$rule_names, 'required' if $required;

  @$rule_names or return;

 RULE: for my $rule_name (@$rule_names) {
    my $rule = $rules->{$rule_name};
    unless ($rule) {
      $rule = $self->_get_cfg_rule($rule_name);
      if ($rule) {
	$rules->{$rule_name} = $rule;
      }
      else {
	print STDERR "** Unknown validation rule $rule_name for $field\n";
      }
    }
    if (!$optional && $rule->{required} && !@data ) {
      $errors->{$field} = _make_error($field, $info, $rule,
				      $info->{required_error} ||
				      $rule->{required_error} || 
				      '$n is a required field');
      last RULE;
    }
    for my $data (@data) {
      if ($rule->{required} && $data !~ /\S/) {
	$errors->{$field} = _make_error($field, $info, $rule, 
					$info->{required_error} ||
					$rule->{required_error} || 
					'$n is a required field');
	last RULE;
      }
      if ($rule->{newconfirm}) {
	my $other = $self->param($rule->{newconfirm});
	if ($other ne '' || $data ne '') {
	  if ($other ne $data) {
	    $errors->{$field} = _make_error($field, $info, $rule,
					    q!$n doesn't match the password!);
	    last RULE;
	  }
	}
      }
      if (defined $rule->{nomatch}) {
	my $match = $rule->{nomatch};
	if ($data =~ /$match/) {
	  $errors->{$field} = _make_error($field, $info, $rule);
	  last RULE;
	}
      }
      if ($data !~ /\S/ && !$rule->{required}) {
	next RULE;
      }
      if ($rule->{match}) {
	my $match = $rule->{match};
	unless ($data =~ /$match/) {
	  $errors->{$field} = _make_error($field, $info, $rule);
	  last RULE;
	}
      }
      if ($rule->{integer}) {
	unless ($data =~ /^\s*([-+]?\d+)\s*$/) {
	  $errors->{$field} = _make_error($field, $info, $rule,
					  '$n must be a whole number');
	  last RULE;
	}
	my $num = $1;
	if (my ($from, $to) = $rule->{integer} =~ /^([+-]?\d+)-([+-]?\d+)$/) {
	  unless ($from <= $num and $num <= $to) {
	    $errors->{$field} = _make_error($field, $info, $rule,
					    $info->{range_error} ||
					    $rule->{range_error} ||
					    "\$n must be in the range $from to $to");
	    last RULE;
	  }
	}
	elsif (my ($from2) = $rule->{integer} =~ /^([+-]?\d+)-$/) {
	  unless ($from2 <= $num) {
	    $errors->{$field} = _make_error($field, $info, $rule,
					    $info->{range_error} ||
					    $rule->{range_error} ||
					    "\$n must be $from2 or higher");
	    last RULE;
	  }
	}
      }
      if ($rule->{date}) {
	unless ($data =~ m!^\s*(\d+)[-+/](\d+)[-+/](\d+)\s*$!) {
	  $errors->{$field} = _make_error($field, $info, $rule,
					  '$n must be a valid date');
	  last RULE;
	}
	my ($day, $month, $year) = ($1, $2, $3);
	if ($day < 1 || $day > 31) {
	  $errors->{$field} = _make_error($field, $info, $rule,
					  '$n must be a valid date - day out of range');
	  last RULE;
	}
	if ($month < 1 || $month > 12) {
	  $errors->{$field} = _make_error($field, $info, $rule,
					  '$n must be a valid date - month out of range');
	  last RULE;
	}
	require DevHelp::Date;
	my $msg;
	unless (($year, $month, $day) = DevHelp::Date::dh_parse_date($data, \$msg)) {
	  $errors->{$field} = $msg;
	  last RULE;
	}
	unless (DevHelp::Date::dh_valid_date($year, $month, $day)) {
	  $errors->{$field} = _make_error($field, $info, $rule,
					  '$n must be a valid date');
	  last RULE;
	}
	if ($rule->{mindate} || $rule->{maxdate}) {
	  my $workdate = sprintf("%04d-%02d-%02d", $year, $month, $day);
	  if ($rule->{mindate}) {
	    my $mindate = DevHelp::Date::dh_parse_date_sql($rule->{mindate});
	    if ($workdate lt $mindate) {
	      $errors->{$field} = 
		_make_error($field, $info, $rule,
			    $info->{mindatemsg} || $rule->{mindatemsg} || '$n is too early');
	    }
	  }
	  if (!$errors->{$field} && $rule->{maxdate}) {
	    my $maxdate = DevHelp::Date::dh_parse_date_sql($rule->{maxdate});
	    if ($workdate gt $maxdate) {
	      $errors->{$field} = 
		_make_error($field, $info, $rule,
			    $info->{mindatemsg} || $rule->{maxdatemsg} || '$n is too late');
	    }
	  }
	}
	if (defined $rule->{dow}) { # could be "0" for Sunday
	  my $dow = DevHelp::Date::dh_date_dow($year, $month, $day);
	  my ($dow_name) = $dow_tokens[$dow];
	  unless ($rule->{dow} =~ /\b($dow|$dow_name)\b/i) {
	    my @valid_dow = map {
	      ;$_ =~ /[0-7]/ ? $dow_names[$_] : $dow_trans{$_}
	    } split /,/, $rule->{dow};
	    my $valid_dow = @valid_dow > 1
	      ? "any of " . join(", ", @valid_dow)
		: "a @valid_dow";
	    $errors->{$field} =
	      _make_error($field, $info, $rule,
			  $info->{dowmsg} || $rule->{dowmsg}
			  || ('$n must fall on ' . $valid_dow));
	    last RULE;
	  }
	}
      }
      if ($rule->{time}) {
	require DevHelp::Date;
	my $msg;
	if (my ($hour, $min, $sec)
	    = DevHelp::Date::dh_parse_time($data, \$msg)) {
	  # nothing to do here yet, later it will allow limits
	}
	else {
	  $errors->{$field} =
	    _make_error($field, $info, $rule,
			'$n is not a valid time of day');
	  last RULE;
	}
      }
      if ($rule->{confirm}) {
	my $other = $self->param($rule->{confirm});
	unless ($other eq $data) {
	  $errors->{$field} = _make_error($field, $info, $rule,
					  q!$n doesn't match the password!);
	  last RULE;
	}
      }
      if ($rule->{notequal}) {
	for my $ne_field (split /,/, $rule->{notequal}) {
	  next if $ne_field eq $field;
	  my $other = $self->param($ne_field);
	  if ($other eq $data) {
	    $errors->{$field} = _make_error
	      (
	       $field, $info, $rule,
	       $info->{ne_error} 
	       || $rule->{ne_error} 
	       || "\$n may not be the same as $ne_field"
	      );
	    last RULE;
	  }
	}
      }
      if ($rule->{ccexpiry}) {
	(my $year_field = $field) =~ s/month/year/;
	
	unless ($data =~ /^\s*\d+\s*$/) {
	  $errors->{$field} = _make_error($field, $info, $rule,
					  q!$n month isn't a number!);
	  last RULE;
	}
	my $year = $self->param($year_field);
	unless (defined $year && $year =~ /\s*\d+\s*$/) {
	  $errors->{$field} = _make_error($field, $info, $rule,
					  q!$n year isn't a number!);
	  last RULE;
	}
	my ($now_year, $now_month) = (localtime)[5, 4];
	$now_year += 1900;
	++$now_month;
	if ($year < $now_year || $year == $now_year && $data < $now_month) {
	  $errors->{$field} = _make_error($field, $info, $rule,
					  q!$n is in the past, your card has expired!);
	  last RULE;
	}
      }
      if ($rule->{ccexpirysingle}) {
	unless ($data =~ m!^\s*(\d+)\s*/\s*(\d+)+\s*$!) {
	  $errors->{$field} = _make_error($field, $info, $rule,
					  q!$n must be in MM/YY format!);
	  last RULE;
	}
	my ($month, $year) = ($1, $2);
	$year += 2000;
	if ($month < 1 || $month > 12) {
	  $errors->{$field} = _make_error($field, $info, $rule,
					  q!$n month must be between 1 and 12!);
	  last RULE;
	}
	my ($now_year, $now_month) = (localtime)[5, 4];
	$now_year += 1900;
	++$now_month;
	if ($year < $now_year || $year == $now_year && $month < $now_month) {
	  $errors->{$field} = _make_error($field, $info, $rule,
					  q!$n is in the past, your card has expired!);
	  last RULE;
	}
      }
      if ($rule->{real}) {
	unless ($data =~ /^\s*$re_real\s*$/) {
	  $errors->{$field} = _make_error($field, $info, $rule,
					  '$n must be a number');
	  last RULE;
	}
	my $num = $1;
	if (my ($from, $to) = $rule->{real} =~ /^$re_real\s*-\s*$re_real$/) {
	  unless ($from <= $num and $num <= $to) {
	    $errors->{$field} = _make_error($field, $info, $rule,
					    $info->{range_error} ||
					    $rule->{range_error} ||
					    "\$n must be in the range $from to $to");
	    last RULE;
	  }
	}
	elsif (my ($from2) = $rule->{real} =~ /^\s*$re_real\s*-$/) {
	  unless ($from2 <= $num) {
	    $errors->{$field} = _make_error($field, $info, $rule,
					    $info->{range_error} ||
					    $rule->{range_error} ||
					    "\$n must be $from2 or higher");
	    last RULE;
	  }
	}
      }
      if ($rule->{file} || $rule->{image}) {
	my $fh = $self->upload($field);
	if ($fh) {
	  my $size = -s $fh;
	  if ($rule->{maxsize} && $size > _kb($rule->{maxbytes})) {
	    $errors->{$field} = _make_error($field, $info, $rule,
					    $info->{maxbytes_error} ||
					    $rule->{maxbytes_error} ||
					    "\$n must be smaller than $rule->{maxsize}");
	    last RULE;
	  }
	  elsif ($rule->{minsize} && $size < _kb($rule->{minsize})) {
	    $errors->{$field} = _make_error($field, $info, $rule,
					    $info->{minbytes_error} ||
					    $rule->{minbytes_error} ||
					    "\$n must be larger than than $rule->{maxsize}");
	    last RULE;
	  }
	}
	else {
	  $errors->{$field} = _make_error($field, $info, $rule,
					  $info->{nofile_error} ||
					  $rule->{nofile_error},
					  "\$n isn't a file");
	  last RULE;
	}
      }
      if ($rule->{image}) {
	my $fh = $self->upload($field);
	require Image::Size;
	my ($width, $height, $type) = Image::Size::imgsize($fh->handle);
	if (!defined $width) {
	  $errors->{$field} =
	    _make_error($field, $info, $rule,
			$info->{notimage_error} || $rule->{notimage_error} ||
			"\$n isn't an image file");
	  last RULE;
	}
	elsif ($rule->{imagetype} &&
	       $rule->{imagetype} !~ /\b\Q$type\E\b/i) {
	  $errors->{$field} =
	    _make_error($field, $info, $rule,
			$info->{imagetype_error} || $rule->{imagetype_error} ||
			"\$n isn't a supported image format");
	  last RULE;
	}
	elsif ($rule->{minwidth} &&
	       $rule->{minwidth} > $width) {
	  $errors->{$field} =
	    _make_error($field, $info, $rule,
			$info->{minwidth_error} || $rule->{minwidth_error} ||
			"\$n must be at least $rule->{minwidth} pixels wide");
	  last RULE;
	}
	elsif ($rule->{minheight} &&
	       $rule->{minheight} > $height) {
	  $errors->{$field} =
	    _make_error($field, $info, $rule,
			$info->{minheight_error} || $rule->{minheight_error} ||
			"\$n must be at least $rule->{minwidth} pixels high");
	  last RULE;
	}
	elsif ($rule->{maxwidth} &&
	       $rule->{maxwidth} < $width) {
	  $errors->{$field} =
	    _make_error($field, $info, $rule,
			$info->{maxwidth_error} || $rule->{maxwidth_error} ||
			"\$n must be no more than $rule->{maxwidth} pixels wide");
	  last RULE;
	}
	elsif ($rule->{maxheight} &&
	       $rule->{maxheight} < $height) {
	  $errors->{$field} =
	    _make_error($field, $info, $rule,
			$info->{maxheight_error} || $rule->{maxheight_error} ||
			"\$n must be no more than $rule->{maxwidth} pixels high");
	  last RULE;
	}
      }
      if ($rule->{ref}) {
	my $method = $rule->{method}
	  or confess "Missing method in ref rule $rule_name";
	my $before = $rule->{before};
	my @before = defined $before ? ( ref $before ? @$before : split /,/, $before ) : ();
	my $after = $rule->{after};
	my @after = defined $after ? ( ref $after ? @$after : split /,/, $after ) : ();
	unless ($rule->{ref}->$method(@before, $data, @after)) {
	  $errors->{$field} = _make_error($field, $info, $rule, 'No such $n');
	  last RULE;
	}
      }
    }
  }
}

sub _make_error {
  my ($field, $info, $rule, $message) = @_;

  $message = $rule->{error} || $message || 'Validation error on field $n';

  my $name = $info->{description} || $field;
  $message =~ s/\$n/$name/g;

  return $message;
}

sub _get_cfg_values_sql {
  my ($field_ref, $cfg, $field, $section, $dbh) = @_;

  $dbh
    or confess "Missing database handle for $section/${field}_values";
  my $groups_sql = $cfg->entry($section, "${field}_values_group_sql");
  my $values_sql = $cfg->entry($section, "${field}_values_sql");
  my $empty_groups = $cfg->entry($section, "${field}_empty_groups");
  
  my $values_sth = $dbh->prepare($values_sql)
    or confess "Cannot prepare $values_sql: ", $dbh->errstr;
  $values_sth->execute
    or confess "Cannot execute $values_sql: ", $values_sth->errstr;
  my @value_rows;
  while (my $row = $values_sth->fetchrow_hashref) {
    push @value_rows, +{ %$row };
  }
  $values_sth->finish;
  if ($groups_sql) {
    my $groups_sth = $dbh->prepare($groups_sql)
      or confess "Cannot prepare $groups_sql: ", $dbh->errstr;
    $groups_sth->execute
      or confess "Cannot execute $groups_sql: ", $groups_sth->errstr;
    my @group_rows;
    while (my $row = $groups_sth->fetchrow_hashref) {
      push @group_rows, +{ %$row };
    }

    if (@group_rows) {
      my %values;
      my %group_ids = map { $_->{id} => 1 } @group_rows;
      my $bad_values;
      my %group_values;

      # collate the values
      for my $value_row (@value_rows) {
	unless (defined $value_row->{group_id}) {
	  ++$bad_values;
	  print STDERR "Row for $field missing group_id\n";
	  last;
	}
	unless ($group_ids{$value_row->{group_id}}) {
	  ++$bad_values;
	  print STDERR "Row for $field $value_row->{id} group id $value_row->{group_id} not in group list\n";
	  last;
	}
	push @{$group_values{$value_row->{group_id}}}, $value_row->{id};
      }
      unless ($bad_values) {
	my @groups;
	for my $group (@group_rows) {
	  my @value_ids;
	  @value_ids = @{$group_values{$group->{id}}}
	    if $group_values{$group->{id}};
	  if ($empty_groups || @value_ids) {
	    push @groups, [ $group->{label}, \@value_ids ];
	  }
	}
	if (@groups) {
	  $field_ref->{value_groups} = \@groups;
	}
      }
      else {
	# fall through and just list the values
	print STDERR "Value rows included group ids which weren't returned in groups - not grouping\n";
      }
    }
    else {
      # fall through and just list the values
      print STDERR "Group sql for $field provided returned no rows\n";
    }
  }

  return map [ $_->{id}, $_->{label} ], @value_rows;
}

sub _get_cfg_groups {
  my ($field_ref, $cfg, $field, $section) = @_;

  my $groups = $cfg->entry($section, "${field}_groups")
    or return;

  my @groups;
  for my $group_entry (split /;/, $groups) {
    my ($label, $ids) = split /=/, $group_entry, 2;
    push @groups, [ $label, [ split /,/, $ids ] ];
  }
  $field_ref->{value_groups} = \@groups;
}

sub _get_cfg_fields {
  my ($rules, $cfg, $section, $field_hash, $dbh) = @_;

  $rules->{rules} = {};
  $rules->{fields} = {};

  my $cfg_fields = $rules->{fields};

  my $fields = $cfg->entry($section, 'fields', '');
  my @names = ( split(/,/, $fields), keys %$field_hash );
  my @extra_config;
  push @extra_config, split /,/, $cfg->entry("form validation", "field_config", "");
  push @extra_config, split /,/, $cfg->entry($section, "field_config", "");

  for my $field (@names) {
    $cfg_fields->{$field} = {};
    for my $cfg_name (qw(required rules description required_error range_error mindatemsg maxdatemsg ne_error), @extra_config) {
      my $value = $cfg->entry($section, "${field}_$cfg_name");
      if (defined $value) {
	$cfg_fields->{$field}{$cfg_name} = $value;
      }
    }

    my $values = $cfg->entry($section, "${field}_values");
    if (defined $values) {
      my @values;
      if ($values eq "-sql") {
	@values = _get_cfg_values_sql($cfg_fields->{$field}, $cfg, $field, $section, $dbh);
      }
      elsif ($values =~ /;/) {
	for my $entry (split /;/, $values) {
	  if ($entry =~ /^([^=]*)=(.*)$/) {
	    push @values, [ $1, $2 ];
	  }
	  else {
	    push @values, [ $entry, $entry ];
	  }
	}
	_get_cfg_groups($cfg_fields->{$field}, $cfg, $field, $section);
      }
      else {
	my $strip;
	if ($values =~ s/:([^:]*)$//) {
	  $strip = $1;
	}
	my %entries = $cfg->entriesCS($values);
	my @order = $cfg->orderCS($values);

	my %seen;
	# we only want the last value in the order
	@order = reverse grep !$seen{$_}++, reverse @order;
	@values = map [ $_, $entries{$_} ], @order;
	if ($strip) {
	  $_->[0] =~ s/^\Q$strip// for @values;
	}
	_get_cfg_groups($cfg_fields->{$field}, $cfg, $field, $section);
      }
      $cfg_fields->{$field}{values} = \@values;
    }
  }
}

sub dh_configure_fields {
  my ($fields, $cfg, $section, $dbh) = @_;

  my %cfg_rules;
  _get_cfg_fields(\%cfg_rules, $cfg, $section, $fields, $dbh);

  # **FIXME** duplicated code
  my $cfg_fields = $cfg_rules{fields};
  for my $field ( keys %$fields ) {
    my $src = $fields->{$field};

    my $dest = $cfg_fields->{$field} || {};

    # the config overrides the software supplied fields
    for my $override (grep $_ ne "rules", keys %$src) {
      if (defined $src->{$override} && !defined $dest->{$override}) {
	$dest->{$override} = $src->{$override};
      }
    }

    # but we add rules
    if ($dest->{rules}) {
      my $rules = $src->{rules} || '';

      # make a copy of the rules array if it's supplied that way so
      # we don't modify someone else's data
      $rules = ref $rules ? [ @$rules ] : [ split /;/, $rules ];

      push @$rules, split /;/, $dest->{rules};
    }
    elsif ($src->{rules}) {
      $dest->{rules} = $src->{rules};
    }

    $cfg_fields->{$field} = $dest if keys %$dest;
  }

  return $cfg_fields;
}

sub _get_cfg_rule {
  my ($self, $rulename) = @_;

  my %rule = $self->{cfg}->entries("Validation Rule $rulename");

  keys %rule or return;

  \%rule;
}

sub dh_fieldnames {
  my ($cfg, $section, $fields) = @_;

  # this needs to be obsoleted now that dh_validate() checks the config

  for my $field (keys %$fields) {
    my $desc = $cfg->entry($section, $field);
    defined $desc and $fields->{$field}{description} = $desc;
  }
}

package DevHelp::Validate::CGI;
use vars qw(@ISA);
@ISA = qw(DevHelp::Validate);

sub param {
  my ($self, $field) = @_;

  $self->{cgi}->param($field);
}

sub upload {
  my ($self, $field) = @_;

  $self->{cgi}->upload($field);
}

sub validate {
  my ($self, $cgi, $errors) = @_;
  
  $self->{cgi} = $cgi;
  
  return $self->_validate($errors);
}

package DevHelp::Validate::Hash;
use vars qw(@ISA);
@ISA = qw(DevHelp::Validate);

sub param {
  my ($self, $field) = @_;

  my $value = $self->{hash}{$field};

  defined $value or return;

  if (ref $value eq 'ARRAY') {
    return @$value;
  }

  return $value;
}

sub upload {
  return;
}

sub validate {
  my ($self, $hash, $errors) = @_;

  $self->{hash} = $hash;

  return $self->_validate($errors);
}

1;

__END__

=head1 NAME

DevHelp::Validate - handy configurable validation, I hope

=head1 SYNOPSIS

  use DevHelp::Validate qw(dh_validate);

  dh_validate($cgi, \%errors, \%rules, $cfg)
    or display_errors(..., \%errors);

=head1 DESCRIPTION

Performs simple validation of CGI or hash data.

=head1 RULES PARAMETER

The rules parameter is a hash with 2 keys:

=over

=item fields

A hash of field names, for each of which the value is a hash.

Each hash can have the following keys:

=over

=item rules

A simple rule name, a ';' separated list of rule names or an array
ref.

=item description

A short description of the field, for use in error messages.

=back

=item rules

A hash of rules.  See the rules description under L<CONFIGURED
VALIDATION>.

=back

=head1 CONFIGURED VALIDATION

Rules can be configured in the database.

For the specified section name, each key is a CGI field name.

The values of those keys gives the name of a validation rule, a string
id for internationlization of the field description and a default
field description, separated by commas.

Each validation rule name has a corresponding section,C<< [Validation
Rule I<rule-name>] >>, which describes the rule.  Rule names can also
refer to built-in rules,

Values in the validation rule section are:

=over

=item required

If this is non-zero the field is required.

=item match

If present, this is used as a regular expression the field must match.

=item nomatch

If present, this is used as a regular expression the field must not
match.

=item error

Message returned as the error if the field fails validation.

=item integer

If set to 1, simply ensures the value is an integer.

If set to a range I<integer>-I<integer> then ensures the value is an
integer in that range.

=item real

If set to 1, simply ensures the value is an real number.

If set to a range C<< I<real> - I<real> >> then ensures the value is
a real number in that range.

=item date

If set to 1, simply validates the value as a date.

Set mindate to specify a minimum date for range validation.  Uses
mindatemsg from the field or rule for the error message.

Set maxdate to specify a maximum date for range validation.  Uses
maxdatemsg from the field or rule for the error message.

Set C<dow> to a comma-separated list of number from 0 to 6, or 3
letter day of week abbreviations to require the date be only on those
days of week.  Uses C<dowmsg> from the field or rule for the error
message.

=item time

If true, validates that the value can be parsed by
L<DevHelp::Date/dh_parse_time()>.

=item confirm

Specify another field that the field must be equal to, intended for
password confirm validation.

=item notequal

A list of field names that may not be equal to the current field.  If
the current field is in the list it is ignored, so you can use one
rule to compare several fields with each other.  Uses ne_error from
the field, or ne_error from the rule for customizing the error
message.

=item ref

Requires that C<method> also be set.

Calls the specified method on the object or class specified by C<ref>
with the value to check as a parameter.  The value is considered value
if the result is true.  This is intended for checking the existence of
objects in a collection.

Optionally C<before> can be an array ref or comma-separated list of
parameters to supply before the value.

Optionally C<after> can be an array ref or comma-separated list of
parameters to supply after the value.

=back

=head1 BUILT-IN RULES

=over

=item email

=item phone

=item postcode

=item url

Matches any valid url, including mailto:, ftp:, etc.  No checking of
the scheme is done.

=item weburl

Matches any valid http or https url.

=item newbieweburl

Matches web URLs with or without "http://" or "https://".

=item confirm

Treats the given field as a confirmation field for a password field
"password".

=item newconfirm

Treats the given field as a confirmation field for an optional
password field "password".

=item required

The field is required.  This should be used where the logic of the
code requires a field, since it cannot be overridden by the config
file.

=item abn

Valid Australian Business Number

=item creditcardnumber

Valid credit card number (no checksum checks are performed).

=item creditcardexpiry

Treats the field as the month part of a credit card expiry date, with
the year field being the field with the same name, but "month"
replaced with "year".  The date of expiry is required to be in the
future.

=item miaa

Valid MIAA membership number.

=item decimal

Valid simple decimal number

=item money

Valid decimal number with 0 or 2 digits after the decimal point.

=item date

A valid date.  Currently dates are limited to Australian format
dd/mm/yy or dd/mm/yyyy format dates.

=item birthdate

A valid date in the past.

=item adultbirthdate

A valid date at least 10 years in the past, at most 100 years in the
past.

=item futuredate

A valid date in the future.

=item time

Parses as a time as per dh_parse_time().

=item integer

Any integer.

=item natural

An integer greater or equal to zero.

=item positiveint

A positive integer.

=item dh_one_line

The field may not contain line breaks

=back

=head1 AUTHOR

Tony Cook <tony@develop-help.com>

=cut
