package BSE::MetaOwnerBase;
use strict;
use Carp 'confess';

our $VERSION = "1.003";

=head1 NAME

BSE::MetaOwnerBase - mix-in for objects that have metadata.

=head1 SYNOPSIS

  my $file = ...
  my @meta = $file->metadata;
  my @text = $file->text_metadata;
  my $meta = $file->meta_by_name($name);
  my @names = $file->metanames;
  my @info = $file->metainfo;
  my @config = $file->meta_config;

=head1 DESCRIPTION

Provides generic metadata support methods.  These can be called on any
L<BSE::TB::ArticleFile> object, and possibly other objects in the
future.

=head1 PUBLIC METHODS

These can be called from anywhere, including templates:

=over

=item metadata

Return all metadata for the object (as metadata objects).

=cut

sub metadata {
  my ($self) = @_;

  require BSE::TB::Metadata;
  return  BSE::TB::Metadata->getBy
    (
     file_id => $self->id,
     owner_type => $self->meta_owner_type,
    );
}

=item text_metadata

Return all metadata for the object with a content type of
C<text/plain>.

=cut

sub text_metadata {
  my ($self) = @_;

  require BSE::TB::Metadata;
  return  BSE::TB::Metadata->getBy
    (
     file_id => $self->id,
     owner_type => $self->meta_owner_type,
     content_type => "text/plain",
    );
}

=item meta_by_name

Retrieve metadata with a specific name.

Returns nothing if there is no metadata of that name.

=cut

sub meta_by_name {
  my ($self, $name) = @_;

  require BSE::TB::Metadata;
  my ($result) = BSE::TB::Metadata->getBy
    (
     file_id => $self->id,
     owner_type => $self->meta_owner_type,
     name => $name
    )
      or return;

  return $result;
}

=item metanames

Returns the names of each metadatum defined for the file.

=cut

sub metanames {
  my ($self) = @_;

  require BSE::TB::Metadata;
  return BSE::TB::Metadata->getColumnBy
    (
     "name",
     [
      [ file_id => $self->id ],
      [ owner_type => $self->meta_owner_type ],
     ],
    );

}

=item metainfo

Returns all but the value for metadata defined for the file.

This is useful to avoid loading large objects if the metadata happens
to be file content.

=cut

sub metainfo {
  my ($self) = @_;

  require BSE::TB::Metadata;
  my @cols = grep $_ ne "value", BSE::TB::MetaEntry->columns;
  return BSE::TB::Metadata->getColumnsBy
    (
     \@cols,
     [
      [ file_id => $self->id ],
      [ owner_type => $self->meta_owner_type ],
     ],
    );
}

=item meta_config

Returns configured metadata fields for this object.

=cut

sub meta_config {
  my ($self, $cfg) = @_;

  $cfg || BSE::Cfg->single;

  require BSE::MetaMeta;
  my @metafields;
  my $prefix = $self->meta_meta_cfg_prefix;
  my @keys = $cfg->orderCS($self->meta_meta_cfg_section);
  for my $name (@keys) {
    my %opts = ( name => $name );
    my $section = "$prefix $name";
    for my $key (BSE::MetaMeta->keys) {
      my $value = $cfg->entry($section, $key);
      if (defined $value) {
	$opts{$key} = $value;
      }
    }
    push @metafields, BSE::MetaMeta->new(%opts, cfg => $cfg);
  }

  return @metafields;

}

=back

=head1 RESTRICTED METHODS

These are not accessible from templates.

=over

=item clear_metadata

Remove all metadata for this object.  Should be called when the object
is removed.

Restricted.

=cut

sub clear_metadata {
  my ($self) = @_;

  BSE::DB->run(bseClearArticleFileMetadata => $self->id, $self->meta_owner_type);
}

=item clear_app_metadata

Remove all application metadata for this object.

Restricted.

=cut

sub clear_app_metadata {
  my ($self) = @_;

  BSE::DB->run(bseClearArticleFileAppMetadata => $self->id, $self->meta_owner_type);
}

=item clear_sys_metadata

Remove all system metadata for this object.

Restricted.

=cut

sub clear_sys_metadata {
  my ($self) = @_;

  BSE::DB->run(bseClearArticleFileSysMetadata => $self->id, $self->meta_owner_type);
}

=item delete_meta_by_name

Remove a single piece of metadata from the object.

Restricted.

=cut

sub delete_meta_by_name {
  my ($self, $name) = @_;

print STDERR "Delete ", $self->id, ",", $name, ",", $self->meta_owner_type, ")\n";
  BSE::DB->run(bseDeleteArticleFileMetaByName => $self->id, $name, $self->meta_owner_type);
}

=item add_meta

Add metadata to the object.

Restricted.

=cut

sub add_meta {
  my ($self, %opts) = @_;

  my $value_text = delete $opts{value_text};
  if ($value_text) {
    utf8::encode($value_text);
    $opts{value} = $value_text;
  }

  require BSE::TB::Metadata;
  return BSE::TB::Metadata->make
      (
       file_id => $self->id,
       owner_type => $self->meta_owner_type,
       %opts,
      );
}

sub restricted_method {
  my ($self, $name) = @_;

  return $name =~ /^(?:clear_|delete_|add_)/;
}

1;

=back

=cut
