package BSE::ImportTargetArticle;
use strict;
use base 'BSE::ImportTargetBase';
use BSE::API qw(bse_make_article bse_add_image bse_add_step_parent);
use Articles;
use Products;
use OtherParents;

sub new {
  my ($class, %opts) = @_;

  my $self = $class->SUPER::new(%opts);

  my $importer = delete $opts{importer};

  my $map = $importer->maps;
  defined $map->{title}
    or die "No title mapping found\n";

  $self->{use_codes} = $importer->cfg_entry('codes', 0);
  $self->{code_field} = $importer->cfg_entry("code_field", $self->default_code_field);

  $self->{parent} = $importer->cfg_entry("parent", $self->default_parent);

  if ($self->{use_codes} && !defined $map->{$self->{code_field}}) {
    die "No product_code mapping found with 'codes' enabled\n";
  }
  $self->{ignore_missing} = $importer->cfg_entry("ignore_missing", 1);
  $self->{reset_images} = $importer->cfg_entry("reset_images", 0);
  $self->{reset_steps} = $importer->cfg_entry("reset_steps", 0);

  return $self;
}

sub start {
  my ($self) = @_;

  $self->{parent_cache} = {};
  $self->{leaves} = [];
  $self->{parents} = [];
}

sub xform_entry {
  my ($self, $importer, $entry) = @_;

  defined $entry->{template}
    or $entry->{template} = $self->leaf_template;

  $entry->{title} =~ /\S/
    or die "title blank\n";

  $entry->{title} =~ /\n/
    and die "Title may not contain newlines";
  $entry->{summary}
    or $entry->{summary} = $entry->{title};
  $entry->{description}
    or $entry->{description} = $entry->{title};
  $entry->{body}
    or $entry->{body} = $entry->{title};
}

sub children_of {
  my ($self, $parent) = @_;

  Articles->children($parent);
}

sub make_parent {
  my ($self, $importer, %entry) = @_;

  return bse_make_article(%entry);
}

sub find_leaf {
  my ($self, $leaf_id) = @_;

  $leaf_id =~ tr/A-Za-z0-9_/_/cds;

  my ($leaf) = Articles->getBy($self->{code_field}, $leaf_id)
    or return;

  return $leaf;
}

sub make_leaf {
  my ($self, $importer, %entry) = @_;

  return bse_make_article(%entry);
}

sub row {
  my ($self, $importer, $entry, $parents) = @_;

  
  $entry->{parentid} = $self->_find_parent($importer, $self->{parent}, @$parents);
  my $leaf;
  if ($self->{use_codes}) {
    my $leaf_id = $entry->{$self->{code_field}};
    
    $leaf = $self->find_leaf($leaf_id);
  }
  if ($leaf) {
    @{$leaf}{keys %$entry} = values %$entry;
    $leaf->save;
    $importer->info("Updated $leaf->{id}: $entry->{title}");
    if ($self->{reset_images}) {
      $leaf->remove_images($importer->cfg);
      $importer->info(" $leaf->{id}: Reset images");
    }
    if ($self->{reset_steps}) {
      my @steps = OtherParents->getBy(childId => $leaf->{id});
      for my $step (@steps) {
	$step->remove;
      }
    }
  }
  else {
    $leaf = $self->make_leaf
      (
       $importer, 
       cfg => $importer->cfg,
       %$entry
      );
    $importer->info("Added $leaf->{id}: $entry->{title}");
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

    my %opts = ( file => $full_file );
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
  for my $step_index (1 .. 10) {
    my $step_id = $entry->{"step$step_index"};
    $step_id
      or next;
    my $step;
    if ($step_id =~ /^\d+$/) {
      $step = Articles->getByPkey($step_id);
    }
    else {
      $step = Articles->getBy(linkAlias => $step_id);
    }
    $step
      or die "Cannot find stepparent with id $step_id\n";

    bse_add_step_parent($importer->cfg, child => $leaf, parent => $step);
  }
  push @{$self->{leaves}}, $leaf;
}

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

sub default_parent { -1 }

sub default_code_field { "linkAlias" }

sub leaves {
  return @{$_[0]{leaves}}
}

sub parents {
  return @{$_[0]{parents}}
}

1;
