package BSE::TB::ArticleFile;
use strict;
# represents a file associated with an article from the database
use base qw(Squirrel::Row BSE::MetaOwnerBase);
use Carp 'confess';

our $VERSION = "1.013";

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

sub fields {
  my ($self, $cfg) = @_;

  $cfg ||= BSE::Cfg->single;

  return
    (
     file =>
     {
      htmltype => "file",
      description => "File",
     },
     description =>
     {
      description => "Description",
      rules => "dh_one_line",
     },
     name =>
     {
      description => "Identifier",
      htmltype => "text",
      width => 20,
     },
     contentType =>
     {
      description => "Content-Type",
      htmltype => "text",
      width => 20,
     },
     notes =>
     {
      description => "Notes",
      htmltype => "textarea",
     },
     forSale =>
     {
      description => "Require payment",
      htmltype => "checkbox",
     },
     download =>
     {
      description => "Treat as download",
      htmltype => "checkbox",
     },
     requireUser =>
     {
      description => "Require login",
      htmltype => "checkbox",
     },
     hide_from_list =>
     {
      description => "Hide from list",
      htmltype => "checkbox",
     },
     storage =>
     {
      description => "Storage",
      htmltype => "select",
      select =>
      {
       id => "id",
       label => "label",
       values =>
       [
	{ id => "", label => "(Auto)" },
	(
	 map
	 +{ id => $_->name, label => $_->description },
	 BSE::TB::ArticleFiles->file_manager($cfg)->all_stores
	),
       ],
      },
     },
    );
}

sub full_filename {
  my ($self, $cfg) = @_;

  $cfg ||= BSE::Cfg->single;

  my $downloadPath = BSE::TB::ArticleFiles->download_path($cfg);
  return $downloadPath . "/" . $self->{filename};
}

sub file_exists {
  my ($self, $cfg) = @_;

  return -f $self->full_filename($cfg);
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
  require BSE::TB::Articles;

  return BSE::TB::Articles->getByPkey($self->{articleId});
}

sub url {
  my ($file, $cfg) = @_;

 #   return "/cgi-bin/user.pl/download_file/$file->{id}";

  $cfg ||= BSE::Cfg->single;

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

sub set_handler {
  my ($self, $cfg) = @_;

  my %errors; # save for later setting into the metadata

  for my $handler_entry (BSE::TB::ArticleFiles->file_handlers($cfg)) {
    my ($key, $handler) = @$handler_entry;
    my $success = eval {
      $self->clear_sys_metadata;
      $handler->process_file($self);
      1;
    };
    if ($success) {
      # set errors from handlers that failed
      for my $key (keys %errors) {
	$self->add_meta(name => "${key}_error",
			value => $errors{$key},
			appdata => 0);
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

sub inline {
  my ($file, %opts) = @_;

  my $cfg = delete $opts{cfg}
    or confess "Missing cfg parameter";

  my $field = delete $opts{field};
  defined $field or $field = "";

  if ($field && exists $file->{$field}) {
    require BSE::Util::HTML;
    return BSE::Util::HTML::escape_html($file->{$field});
  }
  elsif ($field =~ /^meta\.(\w+)$/) {
    my $name = $1;
    my $meta = $file->meta_by_name($name)
      or return "";
    $meta->content_type eq "text/plain"
      or return "* metadata $name isn't text *";

    require BSE::Util::HTML;
    return BSE::Util::HTML::escape_html($meta->value);
  }
  elsif ($field eq "link" || $field eq "url") {
    my $url = "/cgi-bin/user.pl?download_file=1&file=$file->{id}";
    require BSE::Util::HTML;
    my $eurl = BSE::Util::HTML::escape_html($url);
    if ($field eq 'url') {
      return $eurl;
    }
    my $class = $file->{download} ? "file_download" : "file_inline";
    my $html = qq!<a class="$class" href="$eurl">! . BSE::Util::HTML::escape_html($file->{displayName}) . '</a>';
    return $html;
  }
  else {
    my $handler = $file->handler($cfg);
    return $handler->inline($file, $field);
  }

}

# returns file type specific metadata
sub metacontent {
  my ($file, %opts) = @_;
  
  my $cfg = delete $opts{cfg}
    or confess "Missing cfg parameter";

  my $name = delete $opts{name}
    or confess "Missing name parameter";

  my $handler = $file->handler($cfg);
  return $handler->metacontent($file, $name);
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

sub metafields {
  my ($self, $cfg) = @_;

  $cfg ||= BSE::Cfg->single;

  my %metanames = map { $_ => 1 } $self->metanames;

  require BSE::FileMetaMeta;
  my @fields = grep $metanames{$_->name} || $_->cond($self), BSE::FileMetaMeta->all_metametadata($cfg);

  my $handler = $self->handler($cfg);

  my @handler_fields = map BSE::FileMetaMeta->new(%$_, ro => 1, cfg => $cfg), $handler->metametadata;

  return ( @fields, @handler_fields );
}

sub user_orders_for {
  my ($self, $user) = @_;

  require BSE::TB::Orders;
  return BSE::TB::Orders->getSpecial(fileOrdersByUser => $self->id, $user->id);
}

sub downloadable_by {
  my ($self, $user, $error) = @_;

  $self->forSale
    or return 1;

  unless ($user) {
    $$error = 'nouser';
    return;
  }

  my @orders = $self->user_orders_for($user);
  unless (@orders) {
    $$error = 'noorder';
    return;
  }

  if (BSE::TB::ArticleFiles->downloads_must_be_paid) {
    @orders = grep $_->paidFor, @orders;
    unless (@orders) {
      $$error = 'unpaid';
      return;
    }
  }

  if (BSE::TB::ArticleFiles->downloads_must_be_filled) {
    @orders = grep $_->filled, @orders;
    unless (@orders) {
      $$error = 'unfilled';
      return;
    }
  }

  return 1;
}

sub update {
  my ($self, %opts) = @_;

  my $actor = $opts{_actor}
    or confess "Missing _actor parameter";

  my $warnings = $opts{_warnings}
    or confess "Missing _warnings parameter";

  my $cfg = BSE::Cfg->single;
  my $file_dir = BSE::TB::ArticleFiles->download_path($cfg);
  my $old_storage = $self->storage;
  my $delete_file;
  if ($opts{filename} || $opts{file}) {
    my $src_filename = delete $opts{filename};
    my $filename;
    if ($src_filename) {
      if ($src_filename =~ /^\Q$file_dir\E/) {
	# created in the right place, use it
	$filename = $src_filename;
      }
      else {
	open my $in_fh, "<", $src_filename
	  or die "Cannot open $src_filename: $!\n";
	binmode $in_fh;

	require DevHelp::FileUpload;
	my $msg;
	($filename) = DevHelp::FileUpload->
	  make_fh_copy($in_fh, $file_dir, $opts{displayName}, \$msg)
	    or die "$msg\n";
      }
    }
    elsif ($opts{file}) {
      my $file = delete $opts{file};
      require DevHelp::FileUpload;
      my $msg;
      ($filename) = DevHelp::FileUpload->
	make_fh_copy($file, $file_dir, $opts{displayName}, \$msg)
	  or die "$msg\n";
    }

    my $fullpath = $file_dir . '/' . $filename;
    $self->set_filename($filename);
    $self->set_sizeInBytes(-s $fullpath);
    $self->setDisplayName($opts{displayName});

    unless ($opts{contentType}) {
      require BSE::Util::ContentType;
      $self->set_contentType(BSE::Util::ContentType::content_type($cfg, $opts{displayName}));
    }

    $self->set_handler($cfg);
  }

  my $type = delete $opts{contentType};
  if (defined $type) {
    $self->set_contentType($type);
  }

  for my $field (qw(displayName description forSale download requireUser notes hide_from_list category)) {
    my $value = delete $opts{$field};
    if (defined $value) {
      my $method = "set_$field";
      $self->$method($value);
    }
  }

  my $name = $opts{name};
  if (defined $name && $name =~ /\S/) {
    $name =~ /^\w+$/
      or die "name must be a single word\n";
    my ($other) = BSE::TB::ArticleFiles->getBy(articleId => $self->id,
					       name => $name);
    $other && $other->id != $self->id
      and die "Duplicate file name (identifier)\n";

    $self->set_name($name);
  }

  $self->save;

  my $mgr = BSE::TB::ArticleFiles->file_manager($cfg);
  if ($delete_file) {
    if ($old_storage ne "local") {
      $mgr->unstore($delete_file);
    }
    unlink "$file_dir/$delete_file";

    $old_storage = "local";
  }

  my $storage = delete $opts{storage} || '';

  my $new_storage;
  eval {
    $new_storage = 
      $mgr->select_store($self->filename, $storage, $self);
    if ($old_storage ne $new_storage) {
      # handles both new images (which sets storage to local) and changing
      # the storage for old images
      my $src = $mgr->store($self->filename, $new_storage, $self);
      $self->set_src($src);
      $self->set_storage($new_storage);
      $self->save;
    }
    1;
  } or do {
    my $msg = $@;
    chomp $msg;
    require BSE::TB::AuditLog;
    BSE::TB::AuditLog->log
      (
       component => "admin:edit:saveimage",
       level => "warning",
       object => $self,
       actor => $actor,
       msg => "Error saving file to storage $new_storage: $msg",
      );
    push @$warnings, "msg:bse/admin/edit/file/save/savetostore:$msg";
  };

  if ($self->storage ne $old_storage && $old_storage ne "local") {
    eval {
      $mgr->unstore($self->filename, $old_storage);
      1;
    } or do {
      my $msg = $@;
      chomp $msg;
      require BSE::TB::AuditLog;
      BSE::TB::AuditLog->log
	(
	 component => "admin:edit:savefile",
	 level => "warning",
	 object => $self,
	 actor => $actor,
	 msg => "Error saving file to storage $new_storage: $msg",
	);
      push @$warnings, "msg:bse/admin/edit/file/save/delfromstore:$msg";
    };
  }
}

sub meta_owner_type {
  'bse_file';
}

sub meta_meta_cfg_section {
  "global file metadata";
}

sub meta_meta_cfg_prefix {
  "file metadata";
}

sub restricted_method {
  my ($self, $name) = @_;

  return $self->Squirrel::Row::restricted_method($name)
    || $self->BSE::MetaOwnerBase::restricted_method($name);
}

1;
