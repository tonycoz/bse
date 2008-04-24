package BSE::StorageMgr::Base;
use strict;
use Carp 'confess';

sub new {
  my ($class, %opts) = @_;

  $opts{cfg} && $opts{cfg}->can('entry')
    or confess "cfg option missing";

  $opts{debug} = $opts{cfg}->entry('storages', 'debug');

  return bless \%opts, $class;
}

sub store {
  my ($self, $filename, $key, $object) = @_;

  my %http_extras = $self->metadata($object);

  $self->{debug} and print STDERR "StorageMgr: store($filename, $key)\n";

  return $self->_find_store($key)->
    store($self->pathname($filename), $filename, \%http_extras);
}

sub select_store {
  my ($self, $filename, $key, $object) = @_;

  if ($key eq '') {
    my $pathname = $self->pathname($filename);
    for my $store ($self->all_stores) {
      if ($store->match_file($pathname, $filename, $object)) {
	return $store->name;
      }
    }

    return 'local';
  }
  else {
    return $key;
  }
}

sub unstore {
  my ($self, $filename, $key) = @_;

  my $store = $self->_find_store($key)
    or return;

  return $store->unstore($filename);
}

sub cfg {
  $_[0]{cfg};
}

sub all_stores {
  my $self = shift;

  $self->{loaded} or $self->_load_stores;

  return @{$self->{ordered}};
}

sub local_store {
  my $self = shift;

  $self->{loaded} or $self->_load_stores;

  return $self->{local_store};
}

sub pathname {
  my ($self, $filename) = @_;

  my $dir = $self->filebase;
  $dir =~ m![/\\]$! or $dir .= '/';

  return $dir . $filename;
}

sub sync {
  my ($self, %opts) = @_;

  my $print = $opts{print};
  my $noaction = $opts{noaction};

  my @all_files = $self->files;
  for my $store (grep $_->name ne 'local', $self->all_stores) {
    my $name = $store->name;

    $print and $print->("Storage ", $store->description, " ($name)");
    
    my @files = $store->list;
    my %files = map { $_ => 1 } @files;
    my @need_files = grep $_->[1] eq $name, @all_files;
    my %good_files = map { $_->[0] => 1 } grep $files{$_->[0]}, @need_files;
    my @missing_files = grep !$good_files{$_->[0]}, @need_files;
    my @extra_files = grep !$good_files{$_}, @files;

    if (@missing_files) {
      $print
	and $print->("  ", scalar(@missing_files), " missing - transferring:");
      for my $file (@missing_files) {
	$print and $print->("    $file->[0]");
	unless ($noaction) {
	  my $src = $self->store(@$file);
	  $self->set_src($file->[2], $src);
	}
      }
    }
    if (@extra_files) {
      $print and
	$print->("  ", scalar(@extra_files), " extra files found, removing:");
      for my $file (@extra_files) {
	$print and $print->("    $file");
	unless ($noaction) {
	  $self->unstore($file, $name);
	}
      }
    }
  }

  unless ($noaction) {
    my $local_store = $self->local_store;
    for my $file (grep $_->[1] eq 'local', @all_files) {
      $self->set_src($file->[2], $local_store->url($file->[0], $file->[2]));
    }
  }
}

sub fixsrc {
  my $self = shift;

  for my $file ($self->files) {
    my $store = $self->_find_store($file->[1]);
    $self->set_src($file->[2], $store->url($file->[0]));
  }
}

sub url {
  my ($self, $basename, $key, $object) = @_;

  $key = $self->select_store($basename, $key, $object);
  my $store = $self->_find_store($key);
  return $store->url($basename);
}

sub _load_stores {
  my ($self) = @_;

  my @keys = split /,/, $self->cfg->entry('storages', $self->type, '');

  if (grep $_ eq 'local', @keys) {
    die "You cannot include the local storage in the configured storage list\n";
  }

  my %stores;
  my @stores;
  my $cfg = $self->cfg;
  for my $key (@keys) {
    my $section = "storage $key";
    my $class = $cfg->entry($section, 'class')
      or die "No class defined in [$section] for storage $key\n";

    (my $file = $class . ".pm") =~ s(::)(/)g;
    require $file;
    my $store = $class->new(cfg => $cfg, name => $key);

    $stores{$key} = $store;
    push @stores, $store;
  }
  my $local = $self->local_class->new(cfg => $cfg, name => 'local');
  $stores{local} = $local;
  push @stores, $local;
  
  $self->{stores} = \%stores;
  $self->{ordered} = \@stores;
  $self->{local_store} = $local;

  ++$self->{loaded};
}

sub _find_store {
  my ($self, $key) = @_;

  $self->{loaded} or $self->_load_stores;

  my $store = $self->{stores}{$key} 
    or confess "Unknown store $key\n";

  return $store;
}

1;

__END__

=head1 NAME

BSE::StorageMgr::Base - base for storage manages.

=head1 ABSTRACT METHODS

The following methods need to be implemented by concrete storage
manager classes:

=over

=item $mgr->filebase

The base directory files are stored in.

=item $mgr->files

A list of files managed.  This should return a list of array refs,
each contains:

=over

=item *

filename

=item *

storage

=item *

object

=back

=item $mgr->local_class

The class representing the local storage.

=item $mgr->type

The key in [storages] for this file type.

=item $mgr->metadata

Returns HTTP meta data for the file.

=item $mgr->set_src($object, $src)

=back

=cut
