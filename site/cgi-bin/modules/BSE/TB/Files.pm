package BSE::TB::Files;
use strict;
use Squirrel::Table;
use vars qw(@ISA $VERSION);
@ISA = qw(Squirrel::Table);
use BSE::TB::File;
use Carp ();

our $VERSION = "1.004";

sub rowClass {
  return 'BSE::TB::File';
}

sub private_path {
  my ($class) = @_;

  return BSE::Cfg->single->entryVar('paths', 'downloads');
}

sub public_path {
  my ($class) = @_;

  return BSE::Cfg->single->entryVar('paths', 'public_files');
}

sub public_base_url {
  my ($class) = @_;

  return BSE::Cfg->single->entryVar('site', 'public_files');
}

sub make_filename {
  my ($class, $basename, $public, $rmsg) = @_;

  my $base_path = $public ? $class->public_path : $class->private_path;
  require DevHelp::FileUpload;
  my ($file_name, $out_fh) = DevHelp::FileUpload->
    make_img_filename($base_path, $basename, $rmsg)
      or return;

  return ($file_name, $out_fh, "$base_path/$file_name");
}

sub add_cgi_file {
  my ($class, %opts) = @_;

  my $req = delete $opts{req}
    or Carp::confess "No req parameter";
  my $behaviour = delete $opts{behaviour}
    or Carp::confess "No behaviour parameter";
  my $name = delete $opts{name}
    or Carp::confess "No name parameter";
  my $owner;
  unless ($behaviour->unowned) {
    $owner = delete $opts{owner}
      or Carp::confess "No owner parameter";
  }
  my $errors = delete $opts{errors}
    or Carp::confess "No errors parameter";
  my $required = delete $opts{required} || 0;

  my $cgi = $req->cgi;
  my $file_key = $name . "_file";
  my $file_name = $cgi->param($file_key);
  my $file_fh = $cgi->upload($file_key);
  if ($file_name) {
    unless ($file_fh
	    && $ENV{CONTENT_TYPE} =~ m(^multipart/form-data)) {
      $errors->{$file_key} = "Files can only be uploaded as multipart/form-data - check the form enctype";
      return;
    }
    if (-z $file_name) {
      $errors->{$file_key} = "File $file_name is empty";
      return;
    }
  }
  else {
    $required
      and $errors->{$file_key} = "No file specified";
    return;
  }

  my $public = $behaviour->start_public;

  my $msg;
  my ($out_name, $out_fh, $full_path) = 
    BSE::TB::Files->make_filename($file_name, $public, \$msg);
  unless ($out_name) {
    $errors->{$file_key} = $msg;
    return;
  }
  local $/ = \16384;
  binmode $file_fh;
  binmode $out_fh;
  my $size = 0;
  while (<$file_fh>) {
    print $out_fh $_;
    $size += length;
  }
  unless (close $out_fh) {
    $errors->{$file_key} = "Cannot close saved file: $!";
    unlink $full_path;
    return;
  }

  my %file;
  $file{display_name} = $file_name . "";
  $file{filename} = $out_name;
  $file{size_in_bytes} = $size;
  $file{file_type} = $behaviour->file_type;
  $file{owner_id} = $behaviour->owner_id($owner);
  $file{is_public} = $public;

  for my $field (qw/alt url description category name/) {
    my $value = $cgi->param($name . "_" . $field);
    defined $value or $value = "";
    $file{$field} = $value;
  }

  $behaviour->populate(\%file, $full_path);
  my $error;
  unless ($behaviour->validate(\%file, \$error, $owner)) {
    $errors->{$file_key} = $error;
    unlink($full_path);
    return;
  }

  my $file = BSE::TB::Files->make(%file);
  $file->set_src($file->url);
  $file->save;

  return $file;
}

sub save_cgi_file {
  my ($self, %opts) = @_;

  my $req = delete $opts{req}
    or Carp::confess "No req parameter";
  my $behaviour = delete $opts{behaviour}
    or Carp::confess "No behaviour parameter";
  my $name = delete $opts{name}
    or Carp::confess "No name parameter";
  my $owner;
  unless ($behaviour->unowned) {
    $owner = delete $opts{owner}
      or Carp::confess "No owner parameter";
  }
  my $errors = delete $opts{errors}
    or Carp::confess "No errors parameter";
  my $file = delete $opts{file};
  my $old_files = delete $opts{old_files}
    or Carp::confess "No old_files parameter";
  my $new_files = delete $opts{new_files}
    or Carp::confess "No new_files parameter";

  my $cgi = $req->cgi;
  my $file_key = $name . "_file";
  my $file_name = $cgi->param($file_key);
  my $file_fh = $cgi->upload($file_key);
  if ($file_name) {
    unless ($file_fh
	    && $ENV{CONTENT_TYPE} =~ m(^multipart/form-data)) {
      $errors->{$file_key} = "Files can only be uploaded as multipart/form-data - check the form enctype";
      return;
    }
    if (-z $file_name) {
      $errors->{$file_key} = "File $file_name is empty";
      return;
    }

    my $msg;
    my ($out_name, $out_fh, $full_path) = 
      BSE::TB::Files->make_filename($file_name, $file->is_public, \$msg);
    unless ($out_name) {
      $errors->{$file_key} = $msg;
      return;
    }
    local $/ = \16384;
    binmode $file_fh;
    binmode $out_fh;
    my $size = 0;
    while (<$file_fh>) {
      print $out_fh $_;
      $size += length;
    }
    unless (close $out_fh) {
      $errors->{$file_key} = "Cannot close saved file: $!";
      unlink $full_path;
      return;
    }

    push @$old_files, $file->full_filename;
    push @$new_files, $full_path;
    $file->set_filename($out_name);
    $file->set_display_name($file_name . "");
    $file->set_size_in_bytes($size);

    $behaviour->populate($file, $full_path);
    my $error;
    unless ($behaviour->validate($file, \$error, $owner)) {
      $errors->{$file_key} = $error;
      return;
    }
    $file->set_src($file->url);
  }

  for my $field (qw/alt url description category name/) {
    my $value = $cgi->param($name . "_" . $field);
    defined $value or $value = "";
    $file->set($field => $value);
  }

  return $file;
}

=item selected_files

Return the files selected out of a pool for a particular owner.

Returns them in order.

=cut

sub selected_files {
  my ($self, $owner_type, $owner_id) = @_;

  my %files = map { $_->id() => $_ }
    $self->getSpecial(selected_files => $owner_type, $owner_id);

  my @order = $self->selected_file_ids($owner_type, $owner_id);

  return map { $files{$_} ? $files{$_} : () } @order;
}

=item selected_file_ids

Return the id of the files selected out of a pool for a particular
owner.

Returns them in order.

=cut

sub selected_file_ids {
  my ($self, $owner_type, $owner_id) = @_;

  require BSE::TB::SelectedFiles;
  my @order = BSE::TB::SelectedFiles->getColumnBy
    (
     "file_id",
     [ "and" =>
       [ "=", "owner_id", $owner_id ],
       [ "=", "owner_type", $owner_type ]
     ],
     { order => "display_order" }
    );

  return @order;
}

=item set_selected_files

Set the list of selected files for a particular owner.

Also sets the order.

=cut

sub set_selected_files {
  my ($self, $owner_type, $owner_id, $files) = @_;

  # make sure each file exists
  for my $file (@$files) {
    unless (ref $file) {
      BSE::TB::Files->getByPkey($file)
	  or Carp::confess "Bad file id $file";
    }
  }

  require BSE::TB::SelectedFiles;
  BSE::DB->do_txn
      (sub {
	 my @ids = map { ref() ? $_->id : $_ } @$files;

	 my %current = map { $_->file_id() => $_ }
	   BSE::TB::SelectedFiles->getBy2
	       (
		[ "and" =>
		  [ "=", "owner_id", $owner_id ],
		  [ "=", "owner_type", $owner_type ],
		]
	       );

	 my $display_order = 1;
	 for my $id (@ids) {
	   my $sel = delete $current{$id};
	   if ($sel) {
	     $sel->set_display_order($display_order);
	     $sel->save;
	   }
	   else {
	     $sel = BSE::TB::SelectedFiles->make
	       (
		owner_type => $owner_type,
		owner_id => $owner_id,
		file_id => $id,
		display_order => $display_order,
	       );
	   }
	   ++$display_order;
	 }

	 for my $sel (values %current) {
	   $sel->remove;
	 }
       });
}

=item selection_owner_removed

=cut

sub selection_owner_removed {
  my ($self, $owner_type, $owner_id) = @_;

  BSE::DB->single->run("SelectedFiles.remove_owner" => $owner_type, $owner_id);
}

=item owner_removed

Should be called by an owner from it's remove() method to clean up
files of that type.

=cut

sub owner_removed {
  my ($self, $owner_type, $owner_id) = @_;

  my @files = $self->getBy(file_type => $owner_type,
			   owner_id => $owner_id);
  for my $file (@files) {
    $file->remove;
  }
}

1;
