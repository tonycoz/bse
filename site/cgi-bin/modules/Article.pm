package Article;
use strict;
# represents an article from the database
use Squirrel::Row;
use vars qw/@ISA/;
@ISA = qw/Squirrel::Row/;
use Carp 'confess';

sub columns {
  return qw/id parentid displayOrder title titleImage body
    thumbImage thumbWidth thumbHeight imagePos
    release expire keyword template link admin threshold
    summaryLength generator level listed lastModified flags
    customDate1 customDate2 customStr1 customStr2
    customInt1 customInt2 customInt3 customInt4 
    lastModifiedBy created createdBy author pageTitle
    force_dynamic cached_dynamic inherit_siteuser_rights
    metaDescription metaKeywords/;
}

sub numeric {
  qw(id listed parentid threshold summaryLength level 
     customInt1 customInt2 customInt3 customInt4);
}

sub step_parents {
  my ($self) = @_;

  Articles->getSpecial('stepParents', $self->{id});
}

sub visible_step_parents {
  my ($self) = @_;

  use BSE::Util::SQL qw/now_datetime/;
  my $now = now_datetime();
  grep $_->{release} le $now && $now le $_->{expire}, $self->step_parents;
}

sub stepkids {
  my ($self) = @_;

  if ($self->{generator} eq 'Generate::Catalog') {
    require 'Products.pm';
    return Products->getSpecial('stepProducts', $self->{id});
  }
  else {
    return Articles->getSpecial('stepKids', $self->{id});
  }
  return ();
}

sub allstepkids {
  my ($self) = @_;

  return Articles->getSpecial('stepKids', $self->{id});
}

sub visible_stepkids {
  my ($self) = @_;

  use BSE::Util::SQL qw/now_sqldate/;
  my $today = now_sqldate();

  if ($self->{generator} eq 'Generate::Catalog') {
    require 'Products.pm';

    return Products->getSpecial('visibleStep', $self->{id}, $today);
  }
  else {
    return Articles->getSpecial('visibleStepKids', $self->{id}, $today);
  }
  
  return ();
}

# returns a list of all children in the correct sort order
# this is a bit messy
sub allkids {
  my ($self) = @_;

  require 'OtherParents.pm';

  my @otherlinks = OtherParents->getBy(parentId=>$self->{id});
  my @normalkids = Articles->children($self->{id});
  my %order = (
	       (map { $_->{id}, $_->{displayOrder} } @normalkids ),
	       (map { $_->{childId}, $_->{parentDisplayOrder} } @otherlinks),
	      );
  my @stepkids = $self->allstepkids;
  my %kids = map { $_->{id}, $_ } @stepkids, @normalkids;

  return @kids{ sort { $order{$b} <=> $order{$a} } keys %kids };
}

# returns a list of all visible children in the correct sort order
# this is a bit messy
sub all_visible_kids {
  my ($self) = @_;

  Articles->all_visible_kids($self->{id});
}

sub images {
  my ($self) = @_;
  require Images;
  Images->getBy(articleId=>$self->{id});
}

sub children {
  my ($self) = @_;

  return sort { $b->{displayOrder} <=> $b->{displayOrder} } 
    Articles->children($self->{id});
}

sub files {
  my ($self) = @_;

  require ArticleFiles;
  return ArticleFiles->getBy(articleId=>$self->{id});
}

sub parent {
  my ($self) = @_;
  $self->{parentid} == -1 and return;
  return Articles->getByPkey($self->{parentid});
}

sub update_dynamic {
  my ($self, $cfg) = @_;

  $cfg && $cfg->can('entry')
    or confess 'update_dynamic called without $cfg';

  # conditional in case something strange is in the config file
  my $dynamic = $cfg->entry('basic', 'all_dynamic', 0) ? 1 : 0;

  $dynamic or $dynamic = $self->{force_dynamic};

  $dynamic or $dynamic = $self->is_access_controlled;

  $dynamic or $dynamic = $self->force_dynamic_inherited;

  $self->{cached_dynamic} = $dynamic;
}

sub is_dynamic {
  $_[0]{cached_dynamic};
}

sub is_accessible_to {
  my ($self, $group) = @_;

  my $groupid = ref $group ? $group->{id} : $group;

  my @rows = BSE::DB->query(articleAccessibleToGroup => $self->{id}, $groupid);

  scalar @rows;
}

sub group_ids {
  my ($self) = @_;

  map $_->{id}, BSE::DB->query(siteuserGroupsForArticle => $self->{id});
}

sub add_group_id {
  my ($self, $id) = @_;

  eval {
    BSE::DB->single->run(articleAddSiteUserGroup => $self->{id}, $id);
  };
}

sub remove_group_id {
  my ($self, $id) = @_;

  BSE::DB->single->run(articleDeleteSiteUserGroup => $self->{id}, $id);
}

sub is_access_controlled {
  my ($self) = @_;

  my @group_ids = $self->group_ids;
  return 1 if @group_ids;

  return 0
    unless $self->{inherit_siteuser_rights};

  my $parent = $self->parent
    or return 0;

  return $parent->is_access_controlled;
}

sub force_dynamic_inherited {
  my ($self) = @_;

  my $parent = $self->parent
    or return 0;

  $parent->{force_dynamic} && $parent->{flags} =~ /F/
    and return 1;
  
  return $parent->force_dynamic_inherited;
}

sub link_to_filename {
  my ($self, $cfg, $link) = @_;

  $cfg or confess "No \$cfg supplied to ", ref $self, "->link_to_filename";

  defined $link or $link = $self->{link};

  length $link or return;

  my $filename = $link;
  $filename =~ s!/\w*$!!;
  $filename =~ s{^\w+://[\w.-]+(?::\d+)?}{};
  $filename = $Constants::CONTENTBASE . $filename;
  $filename =~ s!//+!/!;
  
  return $filename;
}

sub cached_filename {
  my ($self, $cfg) = @_;

  $cfg or confess "No \$cfg supplied to ", ref $self, "->cached_filename";

  my $dynamic_path = $cfg->entryVar('paths', 'dynamic_cache');
  return $dynamic_path . "/" . $self->{id} . ".html";
}

sub remove {
  my ($self, $cfg) = @_;

  $cfg or confess "No \$cfg supplied to ", ref $self, "->remove";

  require Images;
  my @images = Images->getBy(articleId=>$self->{id});
  my $imagedir = $cfg->entry('paths', 'images', $Constants::IMAGEDIR);
  for my $image (@images) {
    unlink("$imagedir/$image->{image}");
    $image->remove();
  }

  for my $file ($self->files) {
    $file->remove($cfg);
  }
  
  # remove any step(child|parent) links
  require OtherParents;
  my @steprels = OtherParents->anylinks($self->{id});
  for my $link (@steprels) {
    $link->remove();
  }

  # remove the static page
  if ($self->is_dynamic) {
    unlink $self->cached_filename($cfg);
  }
  else {
    unlink $self->link_to_filename($cfg);
  }
  
  $self->SUPER::remove();
}

1;
