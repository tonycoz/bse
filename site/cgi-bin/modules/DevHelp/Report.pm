package DevHelp::Report;
use strict;
use DevHelp::Tags;
use DevHelp::HTML qw(escape_html popup_menu escape_uri);

sub new {
  my ($class, $cfg, $section) = @_;

  return bless { cfg=>$cfg, section=>$section }, $class;
}

sub list_reports {
  my ($self) = @_;

  # we don't list reports with hide set
  my %entries = $self->{cfg}->entries($self->{section});
  my @delete;
  # deleting while iterating is bad
  for my $key (keys %entries) {
    push @delete, $key
      if $self->{cfg}->entry("report $key", "hide");
  }
  delete @entries{@delete};

  %entries;
}

sub report_entry {
  my ($self, $reportid, $entrykey) = @_;

  $self->{cfg}->entry("report $reportid", $entrykey);
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

  $db = $self->report_db($repid, $db);
  my $report = $self->_load($repid, $cgi, $db);

  return
    (
     DevHelp::Tags->make_iterator2(undef, 'field', 'fields', $report->{params}),
     report => [ \&tag_hash, $report ],
     DevHelp::Tags->make_iterator2(undef, 'sort', 'sorts', $report->{sorts}),
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
  $report{debug} = $cfg->entry($repsect, 'debug', 0);

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

  my @sorts;
  my $sort_index = 1;
  while (my $sort = $cfg->entry($repsect, "sort$sort_index")) {
    my ($column, $label, $sql_frag);
    unless (($column, $label, $sql_frag) = split /;/, $sort
	    and $sql_frag) {
      print STDERR "** Invalid sort entry sort$sort_index=$sort in $repsect\n";
      last;
    }
    my $dir = '';
    if ($column =~ s/^([+-])//) {
      $dir = $1;
    }
    push @sorts, 
      { 
       id => $sort_index,
       column => $column, 
       label => $label, 
       sql_frag => $sql_frag,
       dir => $dir,
      };
    ++$sort_index;
  }
  $report{sorts} = \@sorts;

  my @breaks;
  my $break_index = 1;
  while (my $breaks = $cfg->entry($repsect, "break$break_index")) {
    push @breaks, [ grep $_, split /[,;]/, lc $breaks ];
    ++$break_index;
  }
  $report{breaks} = \@breaks;

  @{$report{sql}} or return;
  
  bless \%report, 'DevHelp::Report::Report';
}

sub load {
  goto &_load;
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

  $db = $self->report_db($repid, $db);
  my $report = $self->_load($repid, $cgi, $db);

  my $params = $report->{params};
  return unless @$params;

  my @params;
  my $index = 1;
  for my $param (@$params) {
    my $name = "p$index";

    my $value = $cgi->param($name);
    if (defined $value) {
      if ($param->{type} =~ /^([a-z]+)/) {
	my $typebase = $1;
	$typebase = $validators{$typebase} if exists $validators{$typebase};
	my $method = "_validate_$typebase";
	
	$self->$method($name, $value, $param, $repid, $db, $errors)
	  if $self->can($method);
      }
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

sub tag_levelN_col {
  my ($rrow, $args) = @_;

  defined $$rrow 
    or return '** only inside level1 iterator **';

  exists $$rrow->{$args} or return "** no column $args **";

  escape_html($$rrow->{$args});
}

sub tag_levelN_sum {
  my ($rows, $names, $args) = @_;

  exists $names->{$args} or return "** no column $args **";

  my $index = $names->{$args};
  my $sum = 0;
  for my $row (@$rows) {
    $sum += $row->[$index];
  }

  $sum;
}

sub url {
  my ($self, $report, %opts) = @_;

  my $base = $ENV{SCRIPT_NAME};
  my %args = $self->url_show_args;
  $args{r} = $report->{id};
  if ($opts{sort}) {
    $args{sort} = $opts{sort};
  }
  if ($opts{params}) {
    my $index = 1;
    for my $value (@{$opts{params}}) {
      $args{"p$index"} = $value;
      ++$index;
    }
  }

  $base . '?' . join '&amp;', map { "$_=" . escape_uri($args{$_}) } keys %args;
}

sub tag_sort {
  my ($self, $report, $sort, $params, $titles, $name_index, $arg) = @_;

  my ($col, $field, $rest) = split ' ', $arg;
  if (!defined $col || $col eq '-' || $col =~ /^\s*$/) {
    if ($$name_index >= 0 && $$name_index < @$titles) {
      $col = $titles->[$$name_index];
    }
    else {
      return '** sort - ... only available inside level1_names **';
    }
  }
  my $other_sort;
  my $want_dir = '+';
  if (lc $col eq lc $sort->{column}) {
    $want_dir = $sort->{dir} eq '+' ? '-' : '+';
  }
  ($other_sort) = grep lc $_->{column} eq lc $col && $_->{dir} eq $want_dir, 
    $report->sorts;
  my $new_sort = $other_sort || $sort;
  my $url = $self->url($report, sort => $new_sort->{id}, params => $params);
  if (!defined($field) || $field =~ /^\s*$/) {
    if (grep lc $_->{column} eq lc $col, $report->sorts) {
      return qq!<a href="$url">$col</a>!;
    }
    else {
      return $col;
    }
  }
  elsif ($field eq 'url') {
    return $url;
  }
  elsif ($field eq 'current') {
    return lc $sort->{column} == lc $col;
  }
  elsif ($field eq 'currentdir') {
    return $sort->{id} == $new_sort && $sort->{dir} eq '+';
  }
  elsif ($field eq 'sortable') {
    return (grep lc $_->{column} eq lc $col, $report->sorts) != 0;
  }
  else {
    return "** unknown report sort parameter $field **";
  }
}

sub tag_sort_select {
  my ($self, $report, $sort, $args) = @_;

  my ($action, $rest) = split ' ', $args;
  
  if ($action eq 'others') {
    return scalar(grep $_->{dir} eq '', $report->sorts);
  }
  elsif ($action eq 'select') {
    my @sorts = $report->sorts;
    my %opts = 
      (
       -name => 'sort',
       -labels => { map { $_->{id} => $_->{label} } @sorts },
       -values => [ map $_->{id}, @sorts ],
      );
    $opts{'-default'} = $sort->{id};
    if ($rest) {
      $opts{'-id'} = $rest;
    }
    return popup_menu(%opts);
  }
  else {
    return "** unknown argument '$args' to sort_select **";
  }
}

sub param_prefix {
  'p'
}

sub tag_repparams {
  my ($self, $report, $params, $args) = @_;

  my $prefix = $self->param_prefix;
  defined $args or $args = '';
  if ($args eq 'hidden') {
    return join "\n", 
      map { 
	qq!<input type="hidden" name="$prefix! . ($_+1)
	  . qq!" value="! . escape_html($params->[$_]) . '" />' 
	} 0 .. $#$params;
  }
  elsif ($args eq 'url') {
    return join "&amp;", 
      map $prefix . $_+1 . '=' . escape_uri($params->[$_]),
	  0 .. $#$params;
  }
  else {
    return "** unknown repparams argument $args **";
  }
}

sub show_tags {
  my ($self, $repid, $db, $rmsg, @params) = @_;

  $self->show_tags2($repid, $db, $rmsg, \@params);
}

sub show_tags2 {
  my ($self, $repid, $db, $rmsg, $params, %opts) = @_;

  $db = $self->report_db($repid, $db);

  my $prefix = $opts{tag_prefix} || '';
  # build up result sets
  my $dbh = $db->dbh;
  my $report = $self->_load($repid, undef, $db);
  if ($report->{debug}) {
    print STDERR "Params: @$params\n";
  }
  my @sorts = $report->sorts;
  my $sort;
  if (@sorts) {
    my $sort_id = $opts{sort} || 1;
    ($sort) = grep $_->{id} == $sort_id, @sorts;
  }
  my @results;
  for my $sql (@{$report->{sql}}) {
    my %result;
    my $query = $sql->{sql};
    if ($sort) {
      $query .=  " " . $sort->{sql_frag};
    }
    my $sth = $dbh->prepare($query);
    unless ($sth) {
      $$rmsg = "Error preparing $sql->{sql}: ".$dbh->errstr;
      return;
    }
    my @sqlp = @{$params}[ map $_-1, @{$sql->{params}} ];
    $report->{debug} and print STDERR "sql params: @sqlp\n";
    unless ($sth->execute(@sqlp)) {
      $$rmsg = "Error executing $sql->{sql}: ".$dbh->errstr;
      return;
    }
    my @names_lc = @{$sth->{NAME_lc}};
    $result{names} = \@names_lc;
    $result{names_hash} = 
      { map { $names_lc[$_] => $_ } 0 .. $#names_lc };
    $result{titles} = [ @{$sth->{NAME}} ];
    my @rows;
    while (my $row = $sth->fetchrow_arrayref) {
      push @rows, [ @$row ];
    }
    $result{rows} = \@rows;
    if ($report->{debug}) {
      print STDERR "Result set of ",scalar(@rows)," rows\n";
    }

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
  my $level1_row;
  my $level1_name_index;
  my %tags =
    (
     DevHelp::Tags->make_iterator2
     (undef, $prefix.'level1', $prefix.'level1', $work[0], \$index[0], undef, \$level1_row),
     DevHelp::Tags->make_iterator2
     ([ \&iter_levelN_cols, 0, \@results, $work[0], \$index[0] ], 
      $prefix.'level1_col', $prefix.'level1_cols', undef, undef, 'NoCache'),
     DevHelp::Tags->make_iterator2
     (undef, $prefix.'level1_name', $prefix.'level1_names', 
      [ map +{ 'name' => $_ }, @{$results[0]{titles}} ], \$level1_name_index),
     DevHelp::Tags->make_iterator2
     ([ \&iter_levelN_links, 0, $report->{sql}[0]{links}, $work[0], 
	\$index[0] ], 
      $prefix.'level1_link', $prefix.'level1_links', undef, undef, 'NoCache'),
     "${prefix}level1_byname" => [ \&tag_levelN_col, \$level1_row ],
     "${prefix}level1_sum" => 
     [ \&tag_levelN_sum, $results[0]{rows}, $results[0]{names_hash} ],
     "${prefix}report" => [ \&tag_hash, $report ],
    );
  for my $level (1 .. $#results) {
    my $name = "${prefix}level" . ($level + 1);
    my %work_tags =
      DevHelp::Tags->make_iterator2
	  ([ \&iter_levelN, $report, \@results, \@work, $level, 
	     \$index[$level-1] ], 
	   $name, $name, $work[$level], \$index[$level], 'NoCache');
    @tags{keys %work_tags} = values %work_tags;
  }
  $tags{"${prefix}sort"} = [ tag_sort => $self, $report, $sort, $params, $results[0]{titles}, \$level1_name_index ];
  $tags{"${prefix}sort_select"} = [ tag_sort_select => $self, $report, $sort ];
  $tags{"${prefix}repparams"} = [ tag_repparams => $self, $report, $params ];

  %tags;
}

sub levels {
  my ($self, $repid, $db) = @_;

  $db = $self->report_db($repid, $db);
  my $report = $self->_load($repid, undef, $db);
  scalar @{$report->{sql}};
  # scalar 1+@{$report->{breaks}};
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
    defined $value{value} or $value{value} = '';
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

# sub show_tags {
#   my ($self, $repid, $db, $rmsg, @params) = @_;

#   # build up result sets
#   my $dbh = $db->dbh;
#   my $report = $self->_load($repid, undef, $db);
#   my @results;
#   for my $sql (@{$report->{sql}}) {
#     my %result;
#     my $sth = $dbh->prepare($sql->{sql});
#     unless ($sth) {
#       $$rmsg = "Error preparing $sql->{sql}: ".$dbh->errstr;
#       return;
#     }
#     my @sqlp = @params[ map $_-1, @{$sql->{params}} ];
#     unless ($sth->execute(@sqlp)) {
#       $$rmsg = "Error executing $sql->{sql}: ".$dbh->errstr;
#       return;
#     }
#     my @names_lc = @{$sth->{NAME_lc}};
#     $result{names} = \@names_lc;
#     $result{names_hash} = 
#       map { $names_lc[$_] => $_ } 0 .. $#names_lc;
#     $result{titles} = [ @{$sth->{NAME}} ];
#     my @rows;
#     while (my $row = $sth->fetchrow_arrayref) {
#       push @rows, [ @$row ];
#     }
#     $result{rows} = \@rows;

#     push @results, \%result;
#   }
  
#   # make sure all breaks are in all the sources
#   my %missing_breaks;
#   my $sql_index = 1;
#   for my $result (@results) {
#     for my $break_col (map @$_, @{$report->{breaks}}) {
#       unless (exists $results->{names_hash}{$break_col}) {
# 	print STDERR "Missing break column $break_col from sql$sql_index\n";
# 	++$missing_breaks{$break_col};
#       }
#     }
#     ++$sql_index;
#   }

#   # go through and remove any break levels with missing break columns
#   my @breaks;
#   for my $break ($report->{breaks}) {
#     my @work_breaks = grep !$missing_breaks{$_}, @$break;
#     push @breaks, \@work_breaks if @work_breaks;
#   }
#   my @allbreaks = map @$_, @breaks;

#   # split into bottom level control breaks
#   my @levels;
#   if (@allbreaks) {
#     # split out level 0
#     my %allsegs;
#     my @splitresults;
#     for my $result (@results) {
#       my %split;
#       my @cols = map $result->{names_hash}{$_}, @allbreaks;
#       for my $row (@{$result->{rows}}) {
# 	my $key = join "\0", @$row{@cols};
# 	++$allsegs{$key};
# 	push @{$split{$key}}, $row;
#       }
#       push @splitresults, \%split;
#     }
#     push @levels, \@splitresults;

#     # make up the other levels
#     # first break out the levels by depth
#     my @breaklevels;
#     my @workbreaks;
#     for my $break (@{$report->{breaks}}) {
#       push @workbreaks, @$break;
#       unshift @breaklevels, [ @workbreaks ];
#     }
#     shift @breaklevels; # don't need the last one
    
#     for my $break (@breaklevels) {
#       my %split;
#       my @cols = @$break;
      
#     }
#   }
#   else {
#     push @levels,
#       [
#        map +{ '' => $_->{rows} }, @results;
#       ];
#   }
# }

sub report_db {
    my ($self, $reportid, $db) = @_;

    my $rdb = $self->{cfg}->entry("report $reportid", "db");
    if (defined $rdb &&
        $self->{cfg}->entries("db $rdb"))
    {
        my $newcfg = { config => { %{ $self->{cfg}{config} } } };
        $newcfg->{config}{db} = $newcfg->{config}{lc "db $rdb"};
        bless $newcfg, 'BSE::Cfg';

        return $db->init_another($newcfg);
    }

    return $db;
}

package DevHelp::Report::Report;

sub param_count {
  scalar @{$_[0]{params}};
}

sub sorts {
  return @{$_[0]{sorts}};
}

1;
