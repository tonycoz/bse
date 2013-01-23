package BSE::MetaOwnerBase;
use strict;

our $VERSION = "1.000";

sub clear_metadata {
  my ($self) = @_;

  BSE::DB->run(bseClearArticleFileMetadata => $self->id, $self->meta_owner_type);
}

sub clear_app_metadata {
  my ($self) = @_;

  BSE::DB->run(bseClearArticleFileAppMetadata => $self->id, $self->meta_owner_type);
}

sub clear_sys_metadata {
  my ($self) = @_;

  BSE::DB->run(bseClearArticleFileSysMetadata => $self->id, $self->meta_owner_type);
}

sub delete_meta_by_name {
  my ($self, $name) = @_;

print STDERR "Delete ", $self->id, ",", $name, ",", $self->meta_owner_type, ")\n";
  BSE::DB->run(bseDeleteArticleFileMetaByName => $self->id, $name, $self->meta_owner_type);
}

sub add_meta {
  my ($self, %opts) = @_;

  require BSE::TB::Metadata;
  return BSE::TB::Metadata->make
      (
       file_id => $self->id,
       owner_type => $self->meta_owner_type,
       %opts,
      );
}

sub metadata {
  my ($self) = @_;

  require BSE::TB::Metadata;
  return  BSE::TB::Metadata->getBy
    (
     file_id => $self->id,
     owner_type => $self->meta_owner_type,
    );
}

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

1;
