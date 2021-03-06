package BSE::API;
use strict;
use BSE::Util::SQL qw(sql_datetime now_sqldatetime);
use BSE::DB;
use BSE::Cfg;
use Exporter qw(import);
our @EXPORT_OK = qw(bse_init bse_cfg bse_make_product bse_make_catalog bse_encoding bse_add_image bse_save_image bse_add_step_child bse_add_owned_file bse_delete_owned_file bse_replace_owned_file bse_make_article bse_add_step_parent bse_add_global_image bse_site);
our %EXPORT_TAGS = ( all => \@EXPORT_OK );
use Carp qw(confess croak);
use Fcntl qw(:seek);
use Cwd;

our $VERSION = "1.012";

=head1 NAME

BSE::API - API for fundamental operations for BSE.

=head1 SYNOPSIS

  use BSE::API qw(bse_init);
  bse_init("path/to/bse/cgi-bin");

=head1 DESCRIPTION

BSE::API provides access to a variety of operations for working with
BSE.

For a command-line program, the most essential step is to initialize
BSE, with the bse_init() function:

  bse_init($path);

This is required before calling any other BSE function or method.

=head1 FUNCTIONS

=over

=cut

my %acticle_defaults =
  (
   body => "",
   titleImage => '',
   thumbImage => '',
   thumbWidth => 0,
   thumbHeight => 0,
   imagePos => 'tr',
   release => sql_datetime(time - 86_400),
   expire => '9999-12-31 23:59:59',
   keyword => '',
   template => 'common/default.tmpl',
   link => '', # needs to be set
   admin => '', # needs to be set
   threshold => 5,
   summaryLength => 100,
   generator => 'BSE::Generate::Article',
   # level => undef, # needs to be set
   listed => 1,
   #lastModified => undef, # needs to be set
   flags => '',
   lastModifiedBy => '',
   # created => undef # needs to be set
   createdBy => '',
   force_dynamic => 0,
   cached_dynamic => 0,
   inherit_siteuser_rights => 1,
   metaDescription => '',
   metaKeywords => '',
   summary => '',
   pageTitle => '',
   author => '',
   menu => '',
   titleAlias => '',
   linkAlias => '',
   category => '',
   parentid => -1,
  );

my %product_defaults =
  (
   template => 'shopitem.tmpl',
   parentid => 4,
   generator => 'BSE::Generate::Product',
   wholesalePrice => 0,
   gst => 0,
   leadTime => 0,
   options => '',
   subscription_id => -1,
   subscription_period => 1,
   subscription_usage => 3,
   subscription_required => -1,
   product_code => '',
   weight => 0,
   length => 0,
   height => 0,
   width => 0,
  );

my %catalog_defaults =
  (
   template => 'catalog.tmpl',
   parentid => 3,
   generator => 'BSE::Generate::Catalog',
  );

sub _set_dynamic {
  my ($cfg, $article) = @_;

  if ($article->{parentid} == -1) {
    $article->{level} = 1;
  }
  else {
    require BSE::TB::Articles;
    my $parent = BSE::TB::Articles->getByPkey($article->{parentid})
      or confess "Invalid parent $article->{parentid}\n";
    $article->{level} = $parent->{level} + 1;
  }

  $article->{lastModified} = $article->{created} = now_sqldatetime();
}

sub _finalize_article {
  my ($cfg, $article, $editor_class) = @_;

  my $editor = $editor_class->new(cfg => $cfg, db => BSE::DB->single);

  $article->update_dynamic($cfg);
  $article->setAdmin("/cgi-bin/admin/admin.pl?id=$article->{id}");
  $article->setLink($editor->make_link($article));
  $article->save();
}

{
  my $order;
  sub _next_display_order {
    unless ($order) {
      my ($row) = BSE::DB->query("bse_MaxArticleDisplayOrder");
      $order = $row->{displayOrder} + 1;
    }

    return $order++;
  }
}

my $cfg;

sub bse_cfg {
  my $path = shift || ".";
  $cfg ||= BSE::Cfg->new(path => $path, @_);
  $cfg->entry('site', 'url')
    or confess "Could not load configuration";

  return $cfg;
}

=item bse_init($path)

Initialise the BSE API.

C<$path> should be the BSE F<cgi-bin> directory.

=cut

sub bse_init {
  my ($bse_cgi) = @_;

  defined $bse_cgi
    or confess "Missing bse_cgi parameter";

  unless ($cfg) {
    bse_cfg($bse_cgi);
  }

  BSE::DB->init($cfg);
}

sub bse_make_product {
  my (%opts) = @_;

  my $cfg = delete $opts{cfg}
    or confess "cfg option missing";

  require BSE::TB::Products;

  defined $opts{title} && length $opts{title}
    or confess "Missing title option\n";
  defined $opts{retailPrice} && $opts{retailPrice} =~ /^\d+$/
    or confess "Missing or invalid retailPrice\n";

  $opts{summary} ||= $opts{title};
  $opts{description} ||= $opts{title};
  unless ($opts{displayOrder}) {
    $opts{displayOrder} = _next_display_order();
  }

  %opts =
    (
     %acticle_defaults,
     %product_defaults,
     %opts
    );

  _set_dynamic($cfg, \%opts);

  my @cols = BSE::TB::Product->columns;
  shift @cols;
  my $product = BSE::TB::Products->add(@opts{@cols});

  require BSE::Edit::Product;
  _finalize_article($cfg, $product, 'BSE::Edit::Product');

  return $product;
}

sub bse_make_catalog {
  my (%opts) = @_;

  my $cfg = delete $opts{cfg}
    or confess "cfg option missing";

  require BSE::TB::Articles;

  defined $opts{title} && length $opts{title}
    or confess "Missing title option\n";

  $opts{summary} ||= $opts{title};
  unless ($opts{displayOrder}) {
    $opts{displayOrder} = _next_display_order();
  }

  %opts =
    (
     %acticle_defaults,
     %catalog_defaults,
     %opts
    );

  _set_dynamic($cfg, \%opts);

  my @cols = BSE::TB::Article->columns;
  shift @cols;
  my $catalog = BSE::TB::Articles->add(@opts{@cols});

  require BSE::Edit::Catalog;
  _finalize_article($cfg, $catalog, 'BSE::Edit::Catalog');

  return $catalog;
}

sub bse_make_article {
  my (%opts) = @_;

  my $cfg = delete $opts{cfg}
    or confess "cfg option missing";

  require BSE::TB::Articles;

  defined $opts{title} && length $opts{title}
    or confess "Missing title option\n";

  $opts{summary} ||= $opts{title};
  unless ($opts{displayOrder}) {
    $opts{displayOrder} = _next_display_order();
  }

  %opts =
    (
     %acticle_defaults,
     %opts
    );

  _set_dynamic($cfg, \%opts);

  my @cols = BSE::TB::Article->columns;
  shift @cols;
  my $article = BSE::TB::Articles->add(@opts{@cols});

  require BSE::Edit::Article;
  _finalize_article($cfg, $article, 'BSE::Edit::Article');

  return $article;
}

my %other_parent_defaults =
  (
   release => sql_datetime(time - 86_400),
   expire => '2999-12-31',
  );

sub bse_add_step_child {
  my (%opts) = @_;

  my $cfg = delete $opts{cfg}
    or confess "cfg option missing";

  require BSE::TB::OtherParents;

  my $parent = delete $opts{parent}
    or confess "parent option missing";
  my $child = delete $opts{child}
    or confess "child option missing";
  %opts =
    (
     %other_parent_defaults,
     parentId => $parent->{id},
     childId => $child->{id},
     %opts
    );
  $opts{parentDisplayOrder} ||= _next_display_order();
  $opts{childDisplayOrder} ||= _next_display_order();

  my @cols = BSE::TB::OtherParent->columns;
  shift @cols;

  return BSE::TB::OtherParents->add(@opts{@cols});
}

sub bse_encoding {
  my ($cfg) = @_;

  $cfg && $cfg->can('entry')
    or confess "bse_encoding: Missing cfg parameter\n";

  return $cfg->entry('html', 'charset', 'iso-8859-1');
}

sub bse_add_image {
  my ($cfg, $article, %opts) = @_;

  my $editor;
  ($editor, $article) = _load_editor_class($article, $cfg);

  my $fh;

  my $filename = delete $opts{file};
  if ($filename) {
    open $fh, "< $filename"
      or croak "Failed opening image file $filename: $!";
    binmode $fh;
    $filename = $opts{display_name} if $opts{display_name};
  }
  elsif ($opts{fh}) {
    $filename = $opts{display_name}
      or confess "No image display name supplied with fh";
    $fh = $opts{fh};
  }
  else {
    confess "Missing fh or file parameter";
  }
  my %errors;

  $editor->do_add_image
    (
     $cfg,
     $article,
     $fh,
     %opts,
     errors => $opts{errors} || \%errors,
     filename => $filename,
    );
}

sub bse_language {
  return $cfg->entry("site", "language", "en_AU");
}

{
  my $msgs;

  sub bse_msg_text {
    my ($lang, $id, $parms, $def) = @_;

    unless ($msgs) {
      require BSE::Message;
      $msgs = BSE::Message->new;
    }

    return $msgs->text($lang, $id, $parms, $def);
  }
}

sub bse_save_image {
  my ($image, %opts) = @_;

  my @warn;
  my $result = $image->update
    (
     _language => bse_language(),
     _actor => "S",
     _warnings => \@warn,
     %opts,
    );
  if (@warn) {
    warn "$_\n" for @warn;
  }

  return $result;
}

sub _load_editor_class {
  my ($article, $cfg) = @_;

  require BSE::Edit::Base;
  return BSE::Edit::Base->article_class($article, 'BSE::TB::Articles', $cfg);
}

# File::Copy doesn't like CGI.pm's fake fhs
sub _copy_file_from_fh {
  my ($in_fh, $out_fh) = @_;

  binmode $out_fh;
  binmode $in_fh;
  seek $in_fh, 0, SEEK_SET;
  my $data;
  local $/ = \8192;
  while (defined ($data = <$in_fh>)) {
    print $out_fh $data;
  }

  1;
}

sub bse_add_owned_file {
  my ($cfg, $owner, %opts) = @_;

  defined $opts{display_name} && $opts{display_name} =~ /\S/
    or croak "bse_add_owned_file: display_name must be non-blank";

  defined $opts{title}
    or $opts{title} = $opts{display_name};
  
  unless ($opts{content_type}) {
    require BSE::Util::ContentType;
    $opts{content_type} = BSE::Util::ContentType::content_type($cfg, $opts{display_name});
  }

  my $file = delete $opts{file}
    or die "No source file provided\n";;

  # copy the file to the right place
  require DevHelp::FileUpload;
  my $file_dir = $cfg->entryVar('paths', 'downloads');
  my $msg;
  my ($saved_name, $out_fh) = DevHelp::FileUpload->
    make_img_filename($file_dir, $opts{display_name}, \$msg)
    or die "$msg\n";
  _copy_file_from_fh($file, $out_fh)
    or die "$!\n";
  unless (close $out_fh) {
    die "Error saving file: $!\n";
  }

  $opts{owner_type} = $owner->file_owner_type;
  $opts{size_in_bytes} = -s "$file_dir/$saved_name";
  $opts{owner_id} = $owner->id;
  $opts{category} ||= '';
  $opts{filename} = $saved_name;
  unless ($opts{filekey}) {
    my $fh = IO::File->new("$file_dir/$saved_name", "r");
    if ($fh) {
      require Digest::MD5;
      my $md5 = Digest::MD5->new;
      $md5->addfile($fh);

      $opts{filekey} = $md5->hexdigest;
    }
  }
  
  require BSE::TB::OwnedFiles;
  my $result = BSE::TB::OwnedFiles->make(%opts);

  if ($cfg->entry('notify_files', 'active', 0)) {
    BSE::DB->run(bseAddOwnedFileNotification => $result->id, $owner->file_owner_type, $owner->id);
  }

  return $result;
}

sub bse_delete_owned_file {
  my ($cfg, $owned_file) = @_;

  $owned_file->remove($cfg);
}

sub bse_replace_owned_file {
  my ($cfg, $owned_file, %opts) = @_;

  my $file_dir = $cfg->entryVar('paths', 'downloads');
  my $old_name;
  if ($opts{file}) {
    my $msg;
    require DevHelp::FileUpload;
    my ($saved_name, $out_fh) = DevHelp::FileUpload->
      make_img_filename($file_dir, $opts{display_name}, \$msg)
	or die "$msg\n";
    _copy_file_from_fh($opts{file}, $out_fh)
	or die "$!\n";
    unless (close $out_fh) {
      die "Error saving file: $!\n";
    }
    $old_name = $owned_file->{filename};
    $owned_file->{filename} = $saved_name;
    $owned_file->{size_in_bytes} = -s "$file_dir/$saved_name";
  }

  for my $field (qw/category display_name content_type download title body modwhen size_in_bytes/) {
    defined $opts{$field}
      and $owned_file->{$field} = $opts{$field};
  }
  if ($owned_file->{content_type} eq "") {
    require BSE::Util::ContentType;
    $owned_file->set_content_type(BSE::Util::ContentType::content_type($cfg, $owned_file->{display_name}));
  }

  $owned_file->save;
  $old_name
    and unlink "$file_dir/$old_name";

  1;
}

my %step_defs =
  (
   release => sql_datetime(time - 86_400),
   expire => '2999-12-31',
  );

sub bse_add_step_parent {
  my ($cfg, %opts) = @_;

  my $parent = delete $opts{parent};
  my $child = delete $opts{child};
  my %step =
    (
     %step_defs,
     parentId => $parent->{id},
     childId => $child->{id},
     parentDisplayOrder => _next_display_order(),
     childDisplayOrder => _next_display_order(),
    );

  return BSE::TB::OtherParents->make(%step);
}

=item bse_site

Returns a BSE::TB::Site object, for access to global files and images.

No parameters.

=cut

sub bse_site {
  require BSE::TB::Site;
  return BSE::TB::Site->new;
}

=item bse_add_global_image($cfg, %opts)

Equivalent to:

  bse_add_image($cfg, bse_site(), %opts);

Create a global image.

=cut

sub bse_add_global_image {
  my ($cfg, %opts) = @_;

  return bse_add_image($cfg, bse_site(), %opts);
}

1;

=back

=head1 AUTHOR

Tony Cook <tony@develop-help.com>

=cut
