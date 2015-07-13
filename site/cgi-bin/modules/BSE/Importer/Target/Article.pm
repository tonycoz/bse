package BSE::Importer::Target::Article;
use strict;
use base 'BSE::Importer::Target::Base';
use BSE::API qw(bse_make_article bse_add_image bse_add_step_parent);
use BSE::TB::Articles;
use BSE::TB::Products;
use BSE::TB::OtherParents;

our $VERSION = "1.012";

=head1 NAME

BSE::Importer::Target::Article - import target for articles.

=head1 SYNOPSIS

  [import profile foo]
  ...
  ; these are the defaults
  codes=0
  code_field=linkAlias
  parent=-1
  ignore_missing=1
  reset_images=0
  reset_files=0
  reset_steps=0

  # done by the importer
  my $target = BSE::Importer::Target::Article->new
     (importer => $importer, opts => \%opts)
  ...
  $target->start($imp);
  # for each row:
  $target->row($imp, \%entry, \@parents);


=head1 DESCRIPTION

Provides a target for importing BSE articles.

C<update_only> profiles must provide a mapping for one of C<id> or
C<linkAlias>.

Non-C<update_only> profiles must provide a mapping for C<title>.

=head1 CONFIGURATION

The following extra configuration can be set in the import profile:

=over

=item *

C<codes> - set to true to use the configured C<code_field> to update
existing articles rather than creating new articles.  This is forced
on when the import profile enables C<update_only>.

=item *

C<code_field> - the field to use to identify existing articles.
Default: C<linkAlias> for article imports.

=item *

C<parent> - the base of the tree of parent articles to create the
parent tree under.

=item *

C<ignore_missing> - set to 0 to error on missing image or article
files.  Default: 1.

=item *

C<reset_images> - set to true to delete all images from an article
before adding the imported images.

=item *

C<reset_files> - set to true to delete all files from an article
before adding the imported files.

=item *

C<reset_steps> - set to true to delete all step parents from an
article before adding the imported steps.

=back

=head1 SPECIAL FIELDS

The following fields are used to import extra information into
articles:

=over

=item *

C<< imageI<index>_I<field> >> - used to import images,
eg. C<image1_file> to specify the image file.  Note: images are not
replaced unless C<reset_images> is set.  I<index> is a number from 1
to 10, I<field> can be any of C<file>, C<alt>, C<name>, C<url>,
C<storage>, with the C<file> entry being required.

=item *

C<< stepI<index> >> - specify step parents for the article.  This can
either be the article id or the article link alias.

=item *

C<tags> - this is split on C</> to set the tags for the article.

=back

=head1 METHODS

=over

=item new()

Create a new article import target.  Follows the protocol specified by
L<BSE::Importer::Target::Base>.

=cut

sub new {
  my ($class, %opts) = @_;

  my $self = $class->SUPER::new(%opts);

  my $importer = delete $opts{importer};

  $self->{use_codes} = $importer->cfg_entry('codes', 0);
  my $map = $importer->maps;
  if ($importer->update_only) {
    my $def_code;
    my $found_key = 0;
  KEYS:
    for my $key ($self->key_fields) {
      if ($map->{$key}) {
	$found_key = 1;
	$def_code = $key;
	last KEYS;
      }
    }
    $found_key
      or die "No key field (", join(",", $self->key_fields),
	") mapping found\n";

    $self->{code_field} = $importer->cfg_entry("code_field", $def_code);
    $self->{use_codes} = 1;
  }
  else {
    defined $map->{title}
      or die "No title mapping found\n";

    $self->{code_field} = $importer->cfg_entry("code_field", $self->default_code_field);

  }

  $self->{parent} = $importer->cfg_entry("parent", $self->default_parent);

  if ($self->{use_codes} && !defined $map->{$self->{code_field}}) {
    die "No $self->{code_field} mapping found with 'codes' enabled\n";
  }
  $self->{ignore_missing} = $importer->cfg_entry("ignore_missing", 1);
  $self->{reset_images} = $importer->cfg_entry("reset_images", 0);
  $self->{reset_files} = $importer->cfg_entry("reset_files", 0);
  $self->{reset_steps} = $importer->cfg_entry("reset_steps", 0);

  return $self;
}

=item start()

Start import processing.

=cut

sub start {
  my ($self) = @_;

  $self->{parent_cache} = {};
  $self->{leaves} = [];
  $self->{parents} = [];
}

=item row()

Process a row of data.

=cut

sub row {
  my ($self, $importer, $entry, $parents) = @_;

  $self->xform_entry($importer, $entry);

  if (!$importer->update_only || @$parents) {
    $entry->{parentid} = $self->_find_parent($importer, $self->{parent}, @$parents);
  }

  my $leaf;
  if ($self->{use_codes}) {
    my $leaf_id = $entry->{$self->{code_field}};

    if ($importer->{update_only}) {
      $leaf_id =~ /\S/
	or die "$self->{code_field} blank for update_only profile\n";
    }

    $leaf = $self->find_leaf($leaf_id, $importer);
  }
  if ($leaf) {
    @{$leaf}{keys %$entry} = values %$entry;
    $leaf->mark_modified(actor => $importer->actor);
    $leaf->save;
    $importer->info("Updated $leaf->{id}: ".$leaf->title);
    if ($self->{reset_images}) {
      $leaf->remove_images($importer->cfg);
      $importer->info(" $leaf->{id}: Reset images");
    }
    if ($self->{reset_files}) {
      $leaf->remove_files($importer->cfg);
      $importer->info(" $leaf->{id}: Reset files");
    }
    if ($self->{reset_steps}) {
      my @steps = BSE::TB::OtherParents->getBy(childId => $leaf->{id});
      for my $step (@steps) {
	$step->remove;
      }
    }
  }
  elsif (!$importer->update_only) {
    $entry->{createdBy} ||= ref $importer->actor ? $importer->actor->logon : "";
    $entry->{lastModifiedBy} ||= ref $importer->actor ? $importer->actor->logon : "";
    $self->validate_make_leaf($importer, $entry);
    $leaf = $self->make_leaf
      (
       $importer, 
       cfg => $importer->cfg,
       %$entry
      );
    $importer->info("Added $leaf->{id}: $entry->{title}");
  }
  else {
    die "No leaf found for $entry->{$self->{code_field}} for update_only profile\n";
  }
  for my $image_index (1 .. 10) {
    my $file = $entry->{"image${image_index}_file"};
    $file
      or next;
    my $full_file = $importer->find_file($file);

    unless ($full_file) {
      $self->{ignore_missing}
	and next;
      die "File '$file' not found for image$image_index\n";
    }

    my %opts =
      (
       file => $full_file,
       display_name => $file,
      );
    for my $key (qw/alt name url storage/) {
      my $fkey = "image${image_index}_$key";
      $entry->{$fkey}
	and $opts{$key} = $entry->{$fkey};
    }
    
    my %errors;
    my $im = bse_add_image($importer->cfg, $leaf, %opts, 
			   errors => \%errors);
    $im 
      or die join(", ",map "$_: $errors{$_}", keys %errors), "\n";
    $importer->info(" $leaf->{id}: Add image '$file'");
  }
  $self->_add_files($importer, $entry, $leaf);
  for my $step_index (1 .. 10) {
    my $step_id = $entry->{"step$step_index"};
    $step_id
      or next;
    my $step;
    if ($step_id =~ /^\d+$/) {
      $step = BSE::TB::Articles->getByPkey($step_id);
    }
    else {
      $step = BSE::TB::Articles->getBy(linkAlias => $step_id);
    }
    $step
      or die "Cannot find stepparent with id $step_id\n";

    bse_add_step_parent($importer->cfg, child => $leaf, parent => $step);
  }
  $self->fill_leaf($importer, $leaf, %$entry);
  push @{$self->{leaves}}, $leaf;

  $importer->event(endrow => { leaf => $leaf });
}

sub _add_files {
  my ($self, $importer, $entry, $leaf) = @_;

  my %named_files = map { $_->name => $_ } grep $_->name ne '', $leaf->files;

  for my $file_index (1 .. 10) {
    my %opts;

    my $found = 0;
    for my $key (qw/name displayName storage description forSale download requireUser notes hide_from_list category/) {
      my $fkey = "file${file_index}_$key";
      if (defined $entry->{$fkey}) {
	$opts{$key} = $entry->{$fkey};
	$found = 1;
      }
    }

    my $filename = $entry->{"file${file_index}_file"};
    if ($filename) {
      my $full_file = $importer->find_file($filename);

      unless ($full_file) {
	$self->{ignore_missing}
	  and next;
	die "File '$filename' not found for file$file_index\n";
      }

      $opts{filename} = $full_file;
      $found = 1;
    }

    $found
      or next;

    my $file;
    if ($opts{name}) {
      $file = $named_files{$opts{name}};
    }

    if (!$file && !$opts{filename}) {
      $importer->warn("No file${file_index}_file supplied but other file${file_index}_* field supplied");
      next;
    }

    if ($filename && !$opts{displayName}) {
      unless (($opts{displayName}) = $filename =~ /([^\\\/:]+)$/) {
	$importer->warn("Cannot create displayName for $filename");
	next;
      }
    }

    eval {
      if ($file) {
	my @warnings;
	$file->update
	  (
	   _actor => $importer->actor,
	   _warnings => \@warnings,
	   %opts,
	  );

	$importer->info(" $leaf->{id}: Update file '".$file->displayName ."'");
      }
      else {
	# this dies on failure
	$file = $leaf->add_file
	  (
	   $importer->cfg,
	   %opts,
	   store => 1,
	  );

	$importer->info(" $leaf->{id}: Add file '$filename'");
      }
      1;
    } or do {
      $importer->warn($@);
    };
  }
}

=item xform_entry()

Called by row() to perform an extra data transformation needed.

Currently this forces a non-blank, non-newline title, and defaults the
values of C<summary>, C<description> and C<body> to the title.

=cut

sub xform_entry {
  my ($self, $importer, $entry) = @_;

  if (exists $entry->{title}) {
    $entry->{title} =~ /\S/
      or die "title blank\n";

    $entry->{title} =~ /\n/
      and die "Title may not contain newlines";
  }
  unless ($importer->update_only) {
    $entry->{summary}
      or $entry->{summary} = $entry->{title};
    $entry->{description}
      or $entry->{description} = $entry->{title};
    $entry->{body}
      or $entry->{body} = $entry->{title};
  }

  if (defined $entry->{linkAlias}) {
    $entry->{linkAlias} =~ tr/A-Za-z0-9_-//cd;
  }
}

=item children_of()

Utility method to find the children of a given article.

=cut

sub children_of {
  my ($self, $parent) = @_;

  BSE::TB::Articles->children($parent);
}

=item make_parent()

Create a parent article.

Overridden in the product importer to create catalogs.

=cut

sub make_parent {
  my ($self, $importer, %entry) = @_;

  return bse_make_article(%entry);
}

=item find_leaf()

Find a leave article based on the supplied code.

=cut

sub find_leaf {
  my ($self, $leaf_id, $importer) = @_;

  $leaf_id =~ s/\A\s+//;
  $leaf_id =~ s/\s+\z//;

  my ($leaf) = BSE::TB::Articles->getBy($self->{code_field}, $leaf_id)
    or return;

  $importer->event(find_leaf => { id => $leaf_id, leaf => $leaf });

  return $leaf;
}

=item make_leaf()

Create an article based on the imported data.

Overridden in the product importer to create products.

=cut

sub make_leaf {
  my ($self, $importer, %entry) = @_;

  my $leaf = bse_make_article(%entry);

  $importer->event(make_leaf => { leaf => $leaf });

  return $leaf;
}

=item fill_leaf()

Fill the article some more.

Currently sets the tags.

Overridden by the product target to set product options and tiered
pricing.

=cut

sub fill_leaf {
  my ($self, $importer, $leaf, %entry) = @_;

  if ($entry{tags}) {
    my @tags = split '/', $entry{tags};
    my $error;
    unless ($leaf->set_tags(\@tags, \$error)) {
      die "Error setting tags: $error";
    }
  }

  return 1;
}

=item _find_parent()

Find a parent article.

This method calls itself recursively to work down a tree of parents.

=cut

sub _find_parent {
  my ($self, $importer, $parent, @parents) = @_;

  @parents
    or return $parent;
  my $cache = $self->{parent_cache};
  unless ($cache->{$parent}) {
    my @kids = $self->children_of($parent);
    $cache->{$parent} = \@kids;
  }

  my $title = shift @parents;
  my ($cat) = grep lc $_->{title} eq lc $title, @{$cache->{$parent}};
  unless ($cat) {
    my %opts =
      (
       cfg => $importer->cfg,
       parentid => $parent,
       title => $title,
       body => $title,
      );
    $self->{catalog_template}
      and $opts{template} = $self->{catalog_template};
    $cat = $self->make_parent($importer, %opts);
    $importer->info("Add parent $cat->{id}: $title");
    push @{$cache->{$parent}}, $cat;
  }

  unless ($self->{catseen}{$cat->{id}}) {
    $self->{catseen}{$cat->{id}} = 1;
    push @{$self->{parents}}, $cat;
  }

  return $self->_find_parent($importer, $cat->{id}, @parents);
}

=item default_parent()

Return the default parent id.

Overridden by the product target to return the shop id.

=cut

sub default_parent { -1 }

=item default_code_field()

Return the default code field.

Overridden by the product target to return the C<product_code> field.

=cut

sub default_code_field { "linkAlias" }

=item leaves()

Return the leaf articles created or modified by the import run.

=cut

sub leaves {
  return @{$_[0]{leaves}}
}

=item parents()

Return the parent articles created or used by the import run.

=cut

sub parents {
  return @{$_[0]{parents}}
}

=item key_fields()

Columns that can act as keys.

=cut

sub key_fields {
  return qw(id linkAlias);
}

=item validate_make_leaf

Perform validation only needed on creation

=cut

sub validate_make_leaf {
  my ($self, $importer, $entry) = @_;

  if (defined $entry->{linkAlias} && $entry->{linkAlias} ne '') {
    my $other = BSE::TB::Articles->getBy(linkAlias => $entry->{linkAlias});
    $other
      and die "Duplicate linkAlias value with article ", $other->id, "\n";
  }
}

1;

=back

=head1 AUTHOR

Tony Cook <tony@develop-help.com>

=cut
