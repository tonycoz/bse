package DevHelp::Report;
use strict;
use DevHelp::Tags;
use DevHelp::HTML qw(escape_html popup_menu);

sub new {
  my ($class, $cfg, $section) = @_;

  return bless { cfg=>$cfg, section=>$section }, $class;
}

sub list_reports {
  my ($self) = @_;

  $self->{cfg}->entries($self->{section});
}

sub list_tags {
  my ($self) = @_;

  my %reports = $self->list_reports;
  my @reports =
    map +{
	  id => $_, 
	  name => $reports{$_},
	  has_params => scalar($self->report_needs_prompt($_)),
	 },
	   sort { lc $reports{$a} cmp lc $reports{$b} }
	     keys %reports;

  return
    (
     DevHelp::Tags->make_iterator2(undef, 'report', 'reports', \@reports),
    );
}

sub report_needs_prompt {
  my ($self, $repid) = @_;

  $self->{cfg}->entry("report $repid", 'param1');
}

sub valid_report {
  my ($self, $repid) = @_;

  $self->{cfg}->entry($self->{section}, $repid)
    and $self->{cfg}->entry("report $repid", 'sql1')
}

sub prompt_tags {
  my ($self, $repid, $cgi, $db) = @_;

  my $report = $self->_load($repid, $cgi, $db);

  return
    (
     DevHelp::Tags->make_iterator2(undef, 'field', 'fields', $report->{params}),
     report => [ \&tag_hash, $report ],
     
    );
}

sub _load {
  my ($self, $repid, $cgi, $db) = @_;

  my %report;
  my $cfg = $self->{cfg};
  $report{title} = $cfg->entry($self->{section}, $repid);
  my $repsect = "report $repid";

  my @params;
  my $param_index = 1;
  while (my $param = $cfg->entry($repsect, "param$param_index")) {
    my ($type, $label, $post) = split /,/, $param, 3;
    defined $post or $post = '';
    unless (defined $label) {
      $label = $type;
      $type = 'text40';
    }
    my ($html, $values)
      = $self->_get_type_html($type, $cgi, $param_index, $db);

    push @params, {
		   type => $type,
		   label => $label,
		   html => $html,
		   values => $values,
		  };

    ++$param_index;
  }
  $report{params} = \@params;
  $report{has_params} = @params;
  $report{name} = $cfg->entry($self->{section}, $repid);
  $report{id} = $repid;

  my @sql;
  my $sql_index = 1;
  while (my $sql = $cfg->entry($repsect, "sql$sql_index")) {
    my $params = $cfg->entry($repsect, "sql${sql_index}params");
    my @sql_params;
    my %sql;
    if (defined $params) {
      @sql_params = split /,/, $params;
      for my $sqlp (@sql_params) {
	unless ($sqlp >= 1 && $sqlp <= @params) {
	  undef $params;
	  last;
	}
      }
      defined $params or @sql_params = 1 .. @params;
    }
    if ($sql_index > 1) {
      my $match = $cfg->entry("sql${sql_index}match");
      if ($match) {
	my @match = split /,/,$match;
	for my $mentry (@match) {
	  $mentry = [ split /=/, $mentry ];
	}
	$sql{match} = \@match;
      }
    }
    $sql{sql} = $sql;
    $sql{params} = \@sql_params;

    my @links;
    my $link_index = 1;
    while (my $link = $cfg->entry($repsect, 
				  "sql${sql_index}link$link_index")) {
      push @links, $link;
      ++$link_index;
    }
    $sql{links} = \@links;
    $sql{has_links} = @links;
    $report{"has_level${sql_index}_links"} = @links;

    push @sql, \%sql;
    ++$sql_index;
  }
  $report{sql} = \@sql;
  
  \%report;
}

sub prompt_template {
  my ($self, $repid) = @_;

  my $repsect = "report $repid";
  $self->{cfg}->entry($repsect, 'prompt_template');
}

sub _get_type_html {
  my ($self, $type, $cgi, $index, $db) = @_;

  my $name = "p" . $index;
  my $old = $cgi ? $cgi->param($name) : '';
  defined $old or $old = '';
  $old = escape_html($old);

  if ($type =~ /^text(\d+)$/ || $type =~ m!^text(\d+)/(\d+)$!) {
    my $disp_size = $1;
    my $max_size = defined $2 ? $2 : $1;
    return qq!<input type="text" name="$name" value="$old" size="$disp_size" maxlength="$1" />!;
  }
  elsif ($type eq 'date') {
    return qq!<input type="text" name="$name" value="$old" size="10" maxlength="10" />!;
  }
  elsif ($type eq 'int' || $type eq 'integer') {
    return qq!<input type="text" name="$name" value="$old" size="5" maxlength="10" />!;
  }
  else {
    # a hard one
    my $type_type = $self->{cfg}->entry("report datatype $type", 'type');
    my $method;
    if ($type_type) {
      $method = "_get_type_html_$type_type";
      print STDERR "method $method\n";
      $type_type = undef unless $self->can($method);
    }
    
    unless ($type_type) {
      # something generic
      return qq!Unknown or invalid type '$type' for param$index!;
    }

    return $self->$method($type, $name, $cgi, $db);
  }
}

# generates a popup field
sub _get_type_html_sql {
  my ($self, $type, $name, $cgi, $db) = @_;

  my $sect = "report datatype $type";
  my $sql = $self->{cfg}->entry($sect, 'sql')
    or return qq!** No SQL provided for SQL type '$type' **!;

  my $dbh = $db->dbh;
  my $rows = $dbh->selectall_arrayref($sql);

  unless (@$rows) {
    return $self->{cfg}->
      entry($sect, 'novalues', qq!** no values found for type '$type' **!);
  }
  my @values = map $_->[0], @$rows;
  my %labels = map { $_->[0] => $_->[1] } @$rows;

  my $default = $cgi ? $cgi->param($name) : undef;
  defined $default or $default = $values[0];
  
  return (popup_menu(-name => $name,
		     -values => \@values,
		     -labels => \%labels,
		     -default => $default),
	  \@values );
}

sub _get_type_html_enum {
  my ($self, $type, $name, $cgi, $db) = @_;

  my $sect = "report datatype $type";
  
  my @values = split ',', $self->{cfg}->entry($sect, 'values', '');

  @values
    or return "** no values found for type '$type' **";
  my @labels = split ',', $self->{cfg}->entry($sect, 'labels', '');
  if (@labels < @values) {
    push @labels, @values[@labels .. $#values];
  }

  my %labels;
  @labels{@values} = @labels;
  
  my $default = $cgi ? $cgi->param($name) : undef;
  defined $default or $default = $values[0];
  
  return (popup_menu(-name => $name,
		     -values => \@values,
		     -labels => \%labels,
		     -default => $default),
	  \@values );
}

sub tag_hash {
  my ($hash, $args) = @_;

  my $value = $hash->{$args};
  defined $value or $value = '';

  escape_html($value);
}

my %validators =
  (
   sql => 'enum',
   int => 'integer',
  );

sub validate_params {
  my ($self, $repid, $cgi, $db, $errors) = @_;

  my $report = $self->_load($repid, $cgi, $db);

  my $params = $report->{params};
  return unless @$params;

  my @params;
  my $index = 1;
  for my $param (@$params) {
    my $name = "p$index";

    my $value = $cgi->param($name);
    if (defined $value) {
      $param->{type} =~ /^([a-z]+)$/;
      my $typebase = $1;
      $typebase = $validators{$typebase} if exists $validators{$typebase};
      my $method = "_validate_$typebase";

      $self->$method($name, $value, $param, $repid, $db, $errors)
	if $self->can($method);
    }
    else {
      $errors->{$name} = "No value supplied for $param->{label}";
    }
    push @params, $value;
    ++$index;
  }

  @params;
}

sub validate_text {
  my ($self, $name, $value, $param, $repid, $db, $errors) = @_;

  my $sect = "report $repid";
  my $match = $self->{cfg}->entry($repid, "${name}match");
  my $msg = $self->{cfg}->entry($repid, "${name}msg");

  if (defined $match) {
    unless ($value =~ /$match/) {
      $msg ||= "Invalid value supplied for $param->{label}";
      $errors->{$name} = $value;
    }
  }
}

sub _validate_integer {
  my ($self, $name, $value, $param, $repid, $db, $errors) = @_;

  unless ($value =~ /^\s*[-+]?\d+$/) {
    $errors->{$name} = "Supply an integer for $param->{label}";
    return;
  }
  my $sect = "report $repid";
  my $min = $self->{cfg}->entry($repid, "${name}min");
  my $max = $self->{cfg}->entry($repid, "${name}max");
  my $msg = $self->{cfg}->entry($repid, "${name}msg");

  if (defined $min or defined $max) {
    unless (defined $msg) {
      if (defined $min) {
	if (defined $max) {
	  $msg = "$param->{label} must be between $min and $max";
	}
	else {
	  $msg = "Minimum for $param->{label} is $min";
	}
      }
      else {
	$msg = "Maximum for $param->{label} is $max";
      }
    }
    
    if (defined $min && $value < $min
       || defined $max && $value > $max) {
      $param->{$name} = $msg;
    }
  }
}

sub _validate_enum {
  my ($self, $name, $value, $param, $repid, $db, $errors) = @_;

  my $values = $param->{values};
  unless (grep $value eq $_, @$values) {
    $errors->{$name} = "Please select a value from the list for $param->{label}";
  }
}

sub show_tags {
  my ($self, $repid, $db, $rmsg, @params) = @_;

  # build up result sets
  my $dbh = $db->dbh;
  my $report = $self->_load($repid, undef, $db);
  my @results;
  for my $sql (@{$report->{sql}}) {
    my %result;
    my $sth = $dbh->prepare($sql->{sql});
    unless ($sth) {
      $$rmsg = "Error preparing $sql->{sql}: ".$dbh->errstr;
      return;
    }
    my @sqlp = @params[ map $_-1, @{$sql->{params}} ];
    unless ($sth->execute(@sqlp)) {
      $$rmsg = "Error executing $sql->{sql}: ".$dbh->errstr;
      return;
    }
    my @names_lc = @{$sth->{NAME_lc}};
    $result{names} = \@names_lc;
    $result{names_hash} = 
      map { $names_lc[$_] => $_ } 0 .. $#names_lc;
    $result{titles} = [ @{$sth->{NAME}} ];
    my @rows;
    while (my $row = $sth->fetchrow_arrayref) {
      push @rows, [ @$row ];
    }
    $result{rows} = \@rows;

    push @results, \%result;
  }

  my @index = ( 0 ) x @results;
  my @work;
  push @work, [] for 1 .. @results;
  my @level1names = @{$results[0]{names}};
  for my $row (@{$results[0]{rows}}) {
    my %hashrow =
      map { $level1names[$_] => $row->[$_] } 0..$#$row;
    push @{$work[0]}, \%hashrow;
  }
#   @{$work[0]} = map {; my $row = $_;
# 		     return +{ 
# 			      map { $results[0]{names}[$_] => $row->[$_] },
# 			      0 .. $#$row 
# 			     };
# 		    } ;
  my %tags =
    (
     DevHelp::Tags->make_iterator2
     (undef, 'level1', 'level1', $work[0], \$index[0]),
     DevHelp::Tags->make_iterator2
     ([ \&iter_levelN_cols, 0, \@results, $work[0], \$index[0] ], 
      'level1_col', 'level1_cols', undef, undef, 'NoCache'),
     DevHelp::Tags->make_iterator2
     (undef, 'level1_name', 'level1_names', 
      [ map +{ 'name' => $_ }, @{$results[0]{titles}} ]),
     DevHelp::Tags->make_iterator2
     ([ \&iter_levelN_links, 0, $report->{sql}[0]{links}, $work[0], 
	\$index[0] ], 
      'level1_link', 'level1_links', undef, undef, 'NoCache'),
     
     report => [ \&tag_hash, $report ],
    );
  for my $level (1 .. $#results) {
    my $name = "level" . ($level + 1);
    my %work_tags =
      DevHelp::Tags->make_iterator2
	  ([ \&iter_levelN, $report, \@results, \@work, $level, 
	     \$index[$level-1] ], 
	   $name, $name, $work[$level], \$index[$level], 'NoCache');
    @tags{keys %work_tags} = values %work_tags;
  }

  %tags;
}

sub levels {
  my ($self, $repid, $db) = @_;

  my $report = $self->_load($repid, undef, $db);
  scalar @{$report->{sql}};
}

sub show_template {
  my ($self, $repid) = @_;

  my $repsect = "report $repid";
  $self->{cfg}->entry($repsect, 'show_template');
}

sub iter_levelN_cols {
  my ($level, $results, $rows, $rindex) = @_;

  my $row = $rows->[$$rindex];
  my $names = $results->[$level]{names};
  my @result;
  for my $entry (0..$#$names) {
    my %value;
    $value{value} = $row->{$names->[$entry]};
    $value{name} = $names->[$entry];
    $value{title} = $results->[$level]{titles}[$entry];
    push @result, \%value;
  }

  @result;
}

sub iter_levelN_links {
  my ($level, $links, $rows, $rindex) = @_;

  my $row = $rows->[$$rindex];
  my @links;
  for my $entry (@$links) {
    my $copy = $entry;
    $copy =~ s/\$\{(\w+)\}/exists($row->{lc $1}) ? escape_html($row->{lc $1}) : "Unknown $1"/ge;
    push @links, +{ link => $copy };
  }

  @links;
}

sub iter_levelN {
  my ($report, $results, $work, $level, $rparent, $args) = @_;

  # which columns are we checking?
  my $match = $report->{sql}[$level]{match};
  
  my @parnames = @{$results->[$level-1]{names_lc}};
  my $parent = $work->[$level-1];

  my @pardata = @$parent{map $parnames[$match->[$_][1]-1], 0.. $#$match};

  my $source = $results->[$level]{rows};

  my @out = grep 
    {
      1;
    } @$source;
}

1;
