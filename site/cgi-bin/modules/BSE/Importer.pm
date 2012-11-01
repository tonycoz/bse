package BSE::Importer;
use strict;
use Config;

our $VERSION = "1.002";

=head1 NAME

BSE::Importer - generic import framework

=head1 SYNOPSIS

  [import profile foo]
  map_title=1
  map_linkAlias=2
  set_template=common/default.tmpl
  xform_customInt1 = int(rand 100)

  use BSE::Importer;

  my $profiles = BSE::Importer->profiles($cfg);
  my $imp = BSE::Importer->new(cfg => $cfg, profile => $name);
  $imp->process($filename);

=head1 CONFIGURATION

=head2 [import profiles]

This can be used to provide display names for the defined profiles.

Each key is a profile id and the value is the display name.

=head2 [import profile I<name>]

Defines an import profile, with the following keys:

=over

=item *

C<< map_I<field> >> - defines which column number in the source which
be mapped to the specificed field.  The value must be numeric.

=item *

C<< set_I<field> >> - set the value of the given field to a specific
value.

=item *

C<< xform_I<field> >> - perl code to transform other input values to
the value of the specified field.

=item *

C<cat1>, C<cat2>, C<cat3> - the chain of catalog names leading to a
product.

=item *

C<file_path> - PATH format list of directories to search for attached
files such as images.

=item *

C<source> - the source file type, the source module name is this value
with C<BSE::Importer::Source::> prepended, so a value of C<XLS> will use the
C<BSE::Importer::Source::XLS> module.

=item *

C<target> - the target object type, the target module name is this
value with C<BSE::Importer::Target::> prepended, so a value of
C<Product> will use the C<BSE::Importer::Target::Product> module.

=back

The source and target module may include their own configuration in
this section.

=head1 CLASS METHODS

=over

=item new()

BSE::Importer->new(profile => $profile, ...)

Create a new importer.  Parameters are:

=over

=item *

C<profile> - the import profile to process

=item *

C<cfg> - the BSE::Cfg object to use for configuration

=item *

C<callback> - a sub ref to call for messages generated during
processing.

=back

If the profile is invalid, new() with die with a newline terminated
error message.

=cut

sub new {
  my ($class, %opts) = @_;

  my $cfg = delete $opts{cfg} || BSE::Cfg->single;
  my $profile = delete $opts{profile}
    or die "Missing profile option\n";


  my $self = bless 
    {
     cfg => $cfg,
     profile => $profile,
     section => "import profile $profile",
     callback => scalar(delete $opts{callback}),
    }, $class;

  # field mapping
  my $section = $self->section;
  my %ids = $cfg->entriesCS($section);
  keys %ids
    or die "No entries found for profile $profile\n";
  
  my %map;
  for my $map (grep /^map_\w+$/, keys %ids) {
    (my $out = $map) =~ s/^map_//;
    my $in = $ids{$map};
    $in =~ /^\d+$/
      or die "Mapping for $out not numeric\n";
    $map{$out} = $in;
  }
  $self->{map} = \%map;

  my %set;
  for my $set (grep /^set_\w+$/, keys %ids) {
    (my $out = $set) =~ s/^set_//;
    $set{$out} = $ids{$set};
  }
  $self->{set} = \%set;

  my %xform;
  for my $xform (grep /^xform_\w+$/, keys %ids) {
    (my $out = $xform) =~ s/^xform_//;
    $map{$out}
      or die "Xform for $out but no mapping\n";
    my $code = <<EOS;
sub { (local \$_, my \$product) = \@_;
#line 1 "Xform $xform code"
$ids{$xform};
return \$_
}
EOS
    my $sub = eval $code;
    $sub
      or die "Compilation error for $xform code: $@\n";
    $xform{$out} = $sub;
  }
  $self->{xform} = \%xform;

  my @cats;
  for my $cat (qw/cat1 cat2 cat3/) {
    my $col = $ids{$cat};
    $col and push @cats, $col;
  }
  $self->{cats} = \@cats;

  my $file_path = $self->cfg_entry('file_path', delete $opts{file_path});
  defined $file_path or $file_path = '';
  my @file_path = split /$Config{path_sep}/, $file_path;
  if ($opts{file_path}) {
    unshift @file_path, 
      map 
	{ 
	  split /$Config{path_sep}/, $_ 
	}
	  @{$opts{file_path}};
  }
  $self->{file_path} = \@file_path;


  my $source_type = $self->cfg_entry("source", "XLS");
  $self->{source_class} = "BSE::Importer::Source::$source_type";

  $self->_do_require($self->{source_class});
  $self->{source} = $self->{source_class}->new
    (
     importer => $self,
     opts => \%opts,
    );

  my $target_type = $self->cfg_entry("target", "Product");
  $self->{target_class} = "BSE::Importer::Target::$target_type";
  $self->_do_require($self->{target_class});
  $self->{target} = $self->{target_class}->new
    (
     importer => $self,
     opts => \%opts,
    );


  return $self;
}

=item profiles()

Return a hashref mapping profile names to display names.

=cut

sub profiles {
  my ($class, $cfg) = @_;

  $cfg ||= BSE::Cfg->single;

  my %ids = $cfg->entries("import profiles");
  return \%ids;
}

=back

=head1 OBJECT METHODS

=head2 Processing

=over

=item process()

  $imp->process($filename);

Process the specified file, importing the data.

Note that while the current source treats the argument as a filename,
future sources may treat it as a URL or pretty much anything else.

=cut

sub process {
  my ($self, @source_info) = @_;

  $self->{target}->start($self);
  $self->{source}->each_row($self, @source_info);
}

=item errors()

Valid after process() is called, return a list of errors encountered
during processing.

=cut

sub errors {
  $_[0]{errors}
    and return @{$_[0]{errors}};

  return;
}

=item leaves()

Valid after process() is called, return a list of created imported
objects.

=cut

sub leaves {
  return $_[0]{target}->leaves;
}

=item parents()

Valid after process() is called, return a list of synthesized parent
objects (if any).

=cut

sub parents {
  return $_[0]{target}->parents;
}

=back

=head2 Internal

These are for use my sources and targets.

=over

=item row()

  $imp->row($source)

Called by the source to process each row.

=cut

sub row {
  my ($self, $source) = @_;

  eval {
    my %entry = %{$self->{set}};

    # load from mapping
    my $non_blank = 0;
    for my $col (keys %{$self->{map}}) {
      $entry{$col} = $source->get_column($self->{map}{$col});
      $non_blank ||= $entry{$col} =~ /\S/;
    }
    $non_blank
      or return;
    for my $col (keys %{$self->{xform}}) {
      $entry{$col} = $self->{xform}{$col}->($entry{$col}, \%entry);
    }
    my @parents;
    for my $cat (@{$self->{cats}}) {
      my $value = $source->get_column($cat);
      defined $value && $value =~ /\S/
	and push @parents, $value;
    }
    $self->{target}->row($self, \%entry, \@parents);
  };
  if ($@) {
    my $error = $source->rowid . ": $@";
    $error =~ s/\n\z//;
    $error =~ tr/\n/ /s;
    push @{$self->{errors}}, $error;
    $self->warn("Error: $error");
  }
}

=item _do_require()

Load a module by module name and perform a default import.

=cut

sub _do_require {
  my ($self, $class) = @_;

  (my $file = $class . ".pm") =~ s!::!/!g;

  require $file;
  $file->import;

  1;
}

=item info()

  $imp->info(@msg)

Called by various parts of the system to produce informational messages.

=cut

sub info {
  my ($self, @msg) = @_;

  $self->{callback}
    and $self->{callback}->("@msg");
}

=item warn()

  $imp->warn(@msg);

Called by various parts of the system to produce warning messaged for
the current row.

=cut

sub warn {
  my ($self, @msg) = @_;

  $self->{callback}
    and $self->{callback}->($self->{source}->rowid, ": @msg");
}

=item find_file()

  my $fullname = $imp->find_file($filename)

Search the configured file search path for C<$filename> and return the
full path to the file.

Returns an empty list on failure.

=cut

sub find_file {
  my ($self, $file) = @_;

  for my $path (@{$self->{file_path}}) {
    my $full = "$path/$file";
    -f $full and return $full;
  }

  return;
}

=item section()

Return the configuration section for the profile.

=cut

sub section {
  my ($self) = @_;

  return "import profile $self->{profile}";
}

=item maps()

Return a hash reference mapping field names to column numbers.

=cut

sub maps {
  $_[0]{map};
}

=item cfg()

Return the BSE::Cfg object used to configure the importer.

=cut

sub cfg {
  $_[0]{cfg};
}

=item profile()

Return the profile name.

=cut

sub profile {
  $_[0]{profile};
}

=item cfg_entry()

  my $value = $imp->cfg_entry($key, $default)

Return the specified config value from the section for this profile.

=cut

sub cfg_entry {
  my ($self, $key, $default) = @_;

  return $self->{cfg}->entry($self->{section}, $key, $default);
}

1;

=back

=head1 SEE ALSO

L<BSE::Importer::Source::Base>, L<BSE::Importer::Source::XLS>,
L<BSE::Importer::Target::Base>, L<BSE::Importer::Target::Article>,
L<BSE::Importer::Target::Product>,

=head1 AUTHOR

Tony Cook <tony@develop-help.com>

=cut

