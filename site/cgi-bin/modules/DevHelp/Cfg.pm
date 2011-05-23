package DevHelp::Cfg;
use strict;
use FindBin;
use Carp qw(confess);
use constant CFG_DEPTH => 5; # unused so far
use constant CACHE_AGE => 30;
use constant VAR_DEPTH => 10;

our $VERSION = "1.001";

my %cache;

=head1 NAME

  DevHelp::Cfg - configuration file handling

=head1 SYNOPSIS

  my $cfg = DevHelp::Cfg->new();
  my $entry1 = $cfg->entry($section, $key); # undef on failure
  my $entry2 = $cfg->entryErr($section, $key); # abort on failure
  my $entry3 = $cfg->entryVar($section, $key); # replace variables in value

=head1 DESCRIPTION

Provides a simple configuration file object for BSE.

Currently just provides access to a single config file, but could
later be modified to provide access to one based on the current site,
for use in a mod_perl version of BSE.

=head1 METHODS

=over

=item DevHelp::Cfg->new

Create a new configuration file object.

Parameters:

=over

=item *

filename - the filename to search for (required)

=item *

path - the path to start searching for the config file in, typically
the BSE cgi-bin.

=back

=cut

sub new {
  my ($class, %opts) = @_;

  my $filename = delete $opts{filename};
  defined $filename
    or confess "Missing filename parameter";

  my $file;
  if ($opts{path}) {
    $file = _find_cfg($filename, $opts{path});
  }

  unless ($file) {
    $file = _find_cfg($filename) || _find_cfg($filename, ".")
      or return bless { config => {} }, $class;
  }

  return $class->_load_cfg($file);
}

=item entry($section, $key, $def)

Returns the value of the given $key from section $section.

If the section or key doesn not exist, return undef.

=cut

sub entry {
  my ($self, $section, $key, $def) = @_;

  if (exists $self->{config}{lc $section} 
      && exists $self->{config}{lc $section}{values}{lc $key}) {
    return $self->{config}{lc $section}{values}{lc $key}
  }
  else {
    return $def;
  }
}

=item entries($section)

Returns a keyword/value list of the entries from the given section.

This can be assigned to a hash by the caller.  There is no particular
order to the keys.

The keys are all lower-case.

=cut

sub entries {
  my ($self, $section) = @_;

  if ($self->{config}{lc $section}) {
    return %{$self->{config}{lc $section}{values}};
  }
  return;
}

=item entriesCS($section)

Returns a keyword/value list of the entries from the given section.

This can be assigned to a hash by the caller.  There is no particular
order to the keys.

The keys are in original case.

=cut

sub entriesCS {
  my ($self, $section) = @_;

  if ($self->{config}{lc $section}) {
    return %{$self->{config}{lc $section}{case}};
  }
  return;
}

=item order($section)

Returns a list of keys for the given section.

This can contain duplicates, since included config files may also set
a given key.

=cut

sub order {
  my ($self, $section) = @_;

  if ($self->{config}{lc $section}) {
    return @{$self->{config}{lc $section}{order}};
  }

  return;
}

=item orderCS($section)

Returns a list of keys for the given section.  The keys are returned
in their original case.

This can contain duplicates, since included config files may also set
a given key.

=cut

sub orderCS {
  my ($self, $section) = @_;

  if ($self->{config}{lc $section}) {
    return @{$self->{config}{lc $section}{order_nc}};
  }

  return;
}

=item entryErr($section, $key)

Same as the entry() method, except that it dies if the key or section
does not exist.

=cut

sub entryErr {
  my ($self, $section, $key) = @_;

  my $value = $self->entry($section, $key);
  defined $value
    or $self->_error("Cannot find $key in $section");

  return $value;
}

=item entryVar($section, $key)

Same as the entryErr() method, except that if the value found contains
'$(word1/word2)' it is replaced with the value from section 'word1'
key 'word2', similarly '$(word1)' is replaced with key 'word1' from
the current section.

This is nested.

Dies if any key is not found.

Dies if there are more than 10 levels of variable substitution done.

=cut

sub entryVar {
  my ($self, $section, $key, $depth) = @_;

  $depth ||= 0;
  $depth < VAR_DEPTH
    or $self->_error("Too many levels of variables getting $key from $section");
  my $value = $self->entryErr($section, $key);
  $value =~ s!\$\(([\w ]+)/([\w ]+)\)! $self->entryVar($1, $2, $depth+1) !eg;
  $value =~ s!\$\(([\w ]+)\)! $self->entryVar($section, $1, $depth+1) !eg;

  $value;
}

=item entryIfVar($section, $key)

Same as entryVar(), except that it returns undef if there is no value
for the given section/key.

=cut

sub entryIfVar {
  my ($self, $section, $key) = @_;

  my $value = $self->entry($section, $key);
  if (defined $value) {
    $value = $self->entryVar($section, $key);
  }

  $value;
}

=item entryBool($section, $key, [ $def ])

=cut

sub entryBool {
  my ($self, $section, $key, $def) = @_;

  my $entry = $self->entry($section, $key);
  if (defined $entry) {
    return($entry =~ /^(?:yes|true|y|t|1*)$/i);
  }
  else {
    return $def;
  }
}

=back

=head1 INTERNAL METHODS

=over

=item _find_cfg($name [, $path])

Attempts to find a file $name in $path or one of it's ancestor
directories.  If $path is not supplied use $FindBin::Bin.

Not a method.

=cut

sub _find_cfg {
  my ($name, $path) = @_;

  $path ||= $FindBin::Bin;
  my $depth = 0;
  until (-e "$path/$name" || ++$depth > CFG_DEPTH) {
    $path .= "/..";
  }

  my $file = "$path/$name";
  -e $file or return;

  return $file;
}

=item _load_error($msg)

Displays an error message and exits.

Not a method.

=cut

sub _load_error {
  my ($msg) = @_;

  print "Content-Type: text/html\n\n";
  print "<html><head><title>Configuration Error</title></head>\n";
  print "<body>",CGI::escapeHTML($msg),"</body>\n";
  print "</html>\n";
  exit;
}

=item $self->_load_file($file)

Low level file load.

=cut

sub _load_file {
  my ($self, $file) = @_;

  open CFG, "< $file"
    or return;
  binmode CFG, ":encoding(utf-8)";
  my $section;
  while (<CFG>) {
    chomp;
    next if /^\s*$/ || /^\s*[#;]/;
    if (/^\[([^]]+)\]\s*$/) {
      $section = lc $1;
    }
    elsif (/^\s*([^=\s]+)\s*=\s*(.*)$/) {
      $section or next;
      my ($key, $value) = ($1, $2);
      if ($value =~ /^<<(\w+)$/) {
	$value = _get_heredoc(\*CFG, $file, $1);
	defined $value
	  or last;
      }
      push @{$self->{config}{$section}{order}}, lc $key;
      $self->{config}{$section}{values}{lc $key} = $value;
      push @{$self->{config}{$section}{order_nc}}, $key;
      $self->{config}{$section}{case}{$key} = $value;
    }
  }
  close CFG;

  return 1;
}

=item _replace_vars($value, $section)

=cut

sub _replace_vars{
  my ($self, $value, $section, $key) = @_;

  my $depth = 0;
  while ($depth++ < 20) {
    if ($value =~ m!\$\(([\w ]+)/([\w ]+)\)!) {
      my $var_section = lc $1;
      my $var_key = lc $2;
      my $var_value = $self->entry($var_section, $var_key);
      if (defined $var_value) {
	$value =~ s!\$\($var_section/$var_key\)!$var_value!;
      }
      else {
	warn "Unknown variable key \$($var_section/$var_key) in includes for [$section].$key\n";
	return;
      }
      $section = $var_section;
    }
    if ($value =~ m!\$\(([\w ]+)\)!) {
      my $var_key = lc $1;
      my $var_value = $self->entry($section, $var_key);
      if (defined $var_value) {
	$value =~ s!\$\($var_key\)!$var_value!;
      }
      else {
	warn "Unknown variable key \$($var_key) in includes for [$section].$key\n";
	return;
      }
    }
    return $value;
  }
  warn "Too many replacements in $value\n";

  return;
}

=item _load_cfg($file)

Does the basic load of the config file.

=cut

sub _load_cfg {
  my ($class, $file) = @_;

  if ($cache{$file} && $cache{$file}{when} + CACHE_AGE > time) {
    return $cache{$file};
  }

  my $self = bless
    {
     config => {},
     includes => [],
     when => time,
    }, $class;

  $self->_load_file($file)
    or _load_error("Cannot open config file $file: $!");

  # go through the includes
  my @raw_includes;
  if ($self->{config}{includes}) {
    my $hash = $self->{config}{includes}{values};
    @raw_includes = @$hash{sort keys %$hash};
  }
  my $path = $file;
  $path =~ s![^\\/:]+$!!;
 INCLUDE:
  for my $include (@raw_includes) {
    my $work_include = $self->_replace_vars($include, "includes", $include);
    defined $work_include or next INCLUDE;
    my $full = $work_include =~ m!^(?:\w:)?[/\\]! ? $work_include : "$path$work_include";
    if (-e $full) {
      if (-d $full) {
	# scan the directory
	if (opendir CFGDIR, $full) {
	  my @names = map "$full$_", sort grep /\.cfg$/, readdir CFGDIR;
	  closedir CFGDIR;

	  for my $name (@names) {
	    $self->_load_file($name);
	  }
	}
	else {
	  # it's a directory but we can't read it - probably an error
	  warn "Cannot scan config directory $full: $!\n";
	}
      }
      else {
	$self->_load_file($full);
      }
    }
  }

  $cache{$file} = $self;

  return $self;
}

=item _get_heredoc($fh, $end_marker)

Read in a heredoc.

Strips the last newline.

=cut

sub _get_heredoc {
  my ($fh, $filename, $end_marker) = @_;
  
  my $start = $.; # to report it later
  my $value = '';
  while (my $line = <$fh>) {
    chomp(my $test = $line);
    if ($test eq $end_marker) {
      chomp $value;
      return $value;
    }
    $value .= $line;
  }

  print STDERR "No end to here-doc started line $start of $filename\n";
}

=item _error($msg)

Error handling for entryErr().  Saves the message and dies.

=cut

sub _error {
  my ($self, $msg) = @_;

  $self->{error} = $msg;
  die "$msg\n";
}


1;

=head1 AUTHOR

Tony Cook <tony@develop-help.com>

=cut
