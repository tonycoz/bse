package BSE::Cfg;
use strict;
use FindBin;
use constant MAIN_CFG => 'bse.cfg';
use constant CFG_DEPTH => 5; # unused so far
use constant CACHE_AGE => 30;
use constant VAR_DEPTH => 10;

my %cache;


=head1 NAME

  BSE::Cfg - configuration file for BSE

=head1 SYNOPSIS

  my $cfg = BSE::Cfg->new();
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

=item BSE::Cfg->new

Create a new configuration file object.  Currently takes no
parameters, but may do so in the future.

=cut

sub new {
  my ($class, %opts) = @_;

  #my $file = _find_cfg(MAIN_CFG)
  #  or _load_error("Cannot find config file ".MAIN_CFG);
  my $file = _find_cfg(MAIN_CFG)
    or return bless { config => {} }, $class;

  return $class->_load_cfg($file);
}

=item entry($section, $key)

Returns the value of the given $key from section $section.

If the section or key doesn not exist, return undef.

=cut

sub entry {
  my ($self, $section, $key) = @_;

  $self->{config}{lc $section} 
    && $self->{config}{lc $section}{values}{lc $key};
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
  $value =~ s!\$\((\w+)/(\w+)\)! $self->entryVar($1, $2, $depth+1) !eg;
  $value =~ s!\$\((\w+)\)! $self->entryVar($section, $1, $depth+1) !eg;

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
  print "<html><head><title>BSE Error</title></head>\n";
  print "<body>",CGI::escapeHTML($msg),"</body>\n";
  print "</html>\n";
  exit;
}

=item _load_cfg($file)

Does the basic load of the config file.

=cut

sub _load_cfg {
  my ($class, $file) = @_;

  if ($cache{$file} && $cache{$file}{when} + CACHE_AGE > time) {
    return $cache{$file};
  }

  my $section;
  my %sections;
  open CFG, "< $file"
    or _load_error("Cannot open config file $file: $!");
  while (<CFG>) {
    chomp;
    next if /^\s*$/ || /^\s*[#;]/;
    if (/^\[([^]]+)\]\s*$/) {
      $section = lc $1;
    }
    elsif (/^\s*([^=\s]+)\s*=\s*(.*)$/) {
      $section or next;
      $sections{$section}{values}{lc $1} = $2;
      $sections{$section}{case}{lc $1} = $2;
    }
  }
  close CFG;

  my $self = bless { config=>\%sections, when=>time }, $class;
  $cache{$file} = $self;

  return $self;
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
