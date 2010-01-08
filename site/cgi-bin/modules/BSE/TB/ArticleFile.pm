package BSE::TB::ArticleFile;
use strict;
# represents a file associated with an article from the database
use Squirrel::Row;
use vars qw/@ISA/;
@ISA = qw/Squirrel::Row/;
use Carp 'confess';

sub columns {
  return qw/id articleId displayName filename sizeInBytes description 
            contentType displayOrder forSale download whenUploaded
            requireUser notes name hide_from_list storage src category
            file_handler/;
}

sub table {
  "article_files";
}

sub defaults {
  require BSE::Util::SQL;
  return
    (
     notes => '',
     description => '',
     name => '',
     whenUploaded => BSE::Util::SQL::now_datetime(),
     displayOrder => time,
     src => '',
     file_handler => '',
     forSale => 0,
     download => 0,
     requireUser => 0,
     hide_from_list => 0,
     category => '',
     storage => 'local',
    );
}

sub full_filename {
  my ($self, $cfg) = @_;

  my $downloadPath = BSE::TB::ArticleFiles->download_path($cfg);
  return $downloadPath . "/" . $self->{filename};
}

sub remove {
  my ($self, $cfg) = @_;

  $self->clear_metadata;

  $cfg or confess "No \$cfg supplied to ",ref $self,"->remove()";

  my $filename = $self->full_filename($cfg);
  my $debug_del = $cfg->entryBool('debug', 'file_unlink', 0);
  if ($debug_del) {
    unlink $filename
      or print STDERR "Error deleting $filename: $!\n";
  }
  else {
    unlink $filename;
  }
  
  $self->SUPER::remove();
}

sub article {
  my $self = shift;
  require Articles;

  return Articles->getByPkey($self->{articleId});
}

sub url {
  my ($file, $cfg) = @_;

 #   return "/cgi-bin/user.pl/download_file/$file->{id}";

  $cfg or confess "Missing cfg option";

  if ($file->storage eq "local" 
      || $file->forSale
      || $file->requireUser
      || $cfg->entryBool("downloads", "require_logon", 0)
      || $cfg->entry("downloads", "always_redirect", 0)) {
    return "/cgi-bin/user.pl/download_file/$file->{id}";
  }
  else {
    return $file->src;
  }
}

sub handler {
  my ($self, $cfg) = @_;

  return BSE::TB::ArticleFiles->handler($self->file_handler, $cfg);
}

sub clear_metadata {
  my ($self) = @_;

  BSE::DB->run(bseClearArticleFileMetadata => $self->{id});
}

sub set_handler {
  my ($self, $cfg) = @_;

  my %errors; # save for later setting into the metadata

  for my $handler_entry (BSE::TB::ArticleFiles->file_handlers($cfg)) {
    my ($key, $handler) = @$handler_entry;
    my $success = eval {
      $self->clear_metadata;
      $handler->process_file($self);
      1;
    };
    if ($success) {
      # set errors from handlers that failed
      for my $key (keys %errors) {
	$self->add_meta(name => "${key}_error", value => $errors{$key});
      }
      $self->set_file_handler($key);

      return;
    }
    else {
      $errors{$key} = $@;
      chomp $errors{$key};
    }
  }

  # we should never get here
  $self->set_file_handler("");
  print STDERR "** Ran off the end of ArticleFile->set_handler()\n";
  return;
}

sub add_meta {
  my ($self, %opts) = @_;

  require BSE::TB::ArticleFileMetas;
  return BSE::TB::ArticleFileMetas->make
      (
       file_id => $self->{id},
       %opts,
      );
}

sub metadata {
  my ($self) = @_;

  require BSE::TB::ArticleFileMetas;
  return  BSE::TB::ArticleFileMetas->getBy
    (
     file_id => $self->id
    );
}

sub text_metadata {
  my ($self) = @_;

  require BSE::TB::ArticleFileMetas;
  return  BSE::TB::ArticleFileMetas->getBy
    (
     file_id => $self->id,
     content_type => "text/plain",
    );
}

sub meta_by_name {
  my ($self, $name) = @_;

  require BSE::TB::ArticleFileMetas;
  my ($result) = BSE::TB::ArticleFileMetas->getBy
    (
     file_id => $self->id,
     name => $name
    )
      or return;

  return $result;
}

sub inline {
  my ($file, %opts) = @_;

  my $cfg = delete $opts{cfg}
    or confess "Missing cfg parameter";

  my $field = delete $opts{field};
  defined $field or $field = "";

  if ($field && exists $file->{$field}) {
    return escape_html($file->{$field});
  }
  elsif ($field =~ /^meta\.(\w+)$/) {
    my $name = $1;
    my $meta = $file->meta_by_name($name)
      or return "";
    $meta->content_type eq "text/plain"
      or return "* metadata $name isn't text *";

    return escape_html($meta->value);
  }
  elsif ($field eq "link") {
    my $url = "/cgi-bin/user.pl?download_file=1&file=$file->{id}";
    my $eurl = escape_html($url);
    if ($field eq 'url') {
      return $eurl;
    }
    my $class = $file->{download} ? "file_download" : "file_inline";
    my $html = qq!<a class="$class" href="$eurl">! . escape_html($file->{displayName}) . '</a>';
    return $html;
  }
  else {
    my $handler = $file->handler($cfg);
    return $handler->inline($file, $field);
  }

}

sub apply_storage {
  my ($self, $cfg, $mgr, $storage) = @_;

  defined $storage or $storage = 'local';

  if ($storage ne $self->storage) {
    if ($self->storage ne "local") {
      $mgr->unstore($self->filename, $self->storage);
      $self->set_storage("local");
    }
    if ($storage ne "local") {
      my $src = $mgr->store($self->filename, $storage, $self);
	if ($src) {
	  $self->{src} = $src;
	  $self->{storage} = $storage;
	}
    }
    $self->save;
  }
}

1;
