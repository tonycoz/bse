package BSE::TB::ArticleFiles;
use strict;
use Squirrel::Table;
use vars qw(@ISA $VERSION);
@ISA = qw(Squirrel::Table);
use BSE::TB::ArticleFile;
use Carp qw(confess);

sub rowClass {
  return 'BSE::TB::ArticleFile';
}

sub file_storages {
  my $self = shift;
  return map [ $_->{filename}, $_->{storage}, $_ ], $self->all;
}

sub categories {
  my ($class, $cfg) = @_;

  my @cat_ids = split /,/, $cfg->entry("article file categories", "ids", "");
  grep $_ eq "", @cat_ids
    or unshift @cat_ids, "";

  my @cats;
  for my $id (@cat_ids) {
    my $section = length $id ? "file category $id" : "file category empty";
    my $def_name = length $id ? ucfirst $id : "(None)";
    my $name = $cfg->entry($section, "name", $def_name);
    push @cats, +{ id => $id, name => $name };
  }

  return @cats;
}

sub file_handlers {
  my ($self, $cfg) = @_;

  $cfg or confess "Missing cfg option";

  my @handlers = split /[;,]/, $cfg->entry('basic', 'file_handlers');
  push @handlers, "";

  return map [ $_, $self->handler($_, $cfg) ], @handlers;
}

sub handler {
  my ($self, $id, $cfg) = @_;

  my $key = $id || "default";
  my $class = $id ? $cfg->entry("file handlers", $id) : "BSE::FileHandler::Default";

  (my $file = $class . ".pm") =~ s(::)(/)g;
  require $file;
  return $class->new($cfg);
}

sub download_path {
  my ($class, $cfg) = @_;

  return $cfg->entryVar('paths', 'downloads');
}

sub file_manager {
  my ($self, $cfg) = @_;

  require BSE::StorageMgr::Files;

  return BSE::StorageMgr::Files->new(cfg => $cfg);
}

sub all_metametadata {
  my ($self, $cfg) = @_;

  $cfg
    or confess "Missing cfg parameter";

  require BSE::FileMetaMeta;
  my @metafields;
  my @keys = $cfg->orderCS("global file metadata");
  for my $name (@keys) {
    my %opts = ( name => $name );
    my $section = "file metadata $name";
    for my $key (BSE::FileMetaMeta->keys) {
      my $value = $cfg->entry($section, $key);
      if (defined $value) {
	$opts{$key} = $value;
      }
    }
    push @metafields, BSE::FileMetaMeta->new(%opts, cfg => $cfg);
  }

  return @metafields;
}

1;
