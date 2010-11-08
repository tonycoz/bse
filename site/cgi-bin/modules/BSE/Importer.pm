package BSE::Importer;
use strict;
use Config;

our $VERSION = "1.000";

sub new {
  my ($class, %opts) = @_;

  my $cfg = delete $opts{cfg}
    or die "Missing cfg option\n";
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
    my $code = "sub { (local \$_, my \$product) = \@_; \n".$ids{$xform}."\n; return \$_ }";
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
  $self->{source_class} = "BSE::ImportSource$source_type";

  $self->_do_require($self->{source_class});
  $self->{source} = $self->{source_class}->new
    (
     importer => $self,
     opts => \%opts,
    );

  my $target_type = $self->cfg_entry("target", "Product");
  $self->{target_class} = "BSE::ImportTarget$target_type";
  $self->_do_require($self->{target_class});
  $self->{target} = $self->{target_class}->new
    (
     importer => $self,
     opts => \%opts,
    );


  return $self;
}

sub profiles {
  my ($class, $cfg) = @_;

  my %ids = $cfg->entries("import profiles");
  return \%ids;
}

sub section {
  my ($self) = @_;

  return "import profile $self->{profile}";
}

sub maps {
  $_[0]{map};
}

sub cfg {
  $_[0]{cfg};
}

sub profile {
  $_[0]{profile};
}

sub cfg_entry {
  my ($self, $key, $default) = @_;

  return $self->{cfg}->entry($self->{section}, $key, $default);
}

sub process {
  my ($self, @source_info) = @_;

  $self->{target}->start($self);
  $self->{source}->each_row($self, @source_info);
}

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

sub errors {
  $_[0]{errors}
    and return @{$_[0]{errors}};

  return;
}

sub _do_require {
  my ($self, $class) = @_;

  (my $file = $class . ".pm") =~ s!::!/!g;

  require $file;
  $file->import;

  1;
}

sub info {
  my ($self, @msg) = @_;

  $self->{callback}
    and $self->{callback}->("@msg");
}

sub warn {
  my ($self, @msg) = @_;

  $self->{callback}
    and $self->{callback}->($self->{source}->rowid, ": @msg");
}

sub find_file {
  my ($self, $file) = @_;

  for my $path (@{$self->{file_path}}) {
    my $full = "$path/$file";
    -f $full and return $full;
  }

  return;
}

sub leaves {
  return $_[0]{target}->leaves;
}

sub parents {
  return $_[0]{target}->parents;
}

1;
