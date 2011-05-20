package Article;
use strict;
# represents an article from the database
use Squirrel::Row;
use BSE::TB::SiteCommon;
use vars qw/@ISA/;
@ISA = qw/Squirrel::Row BSE::TB::SiteCommon/;
use Carp 'confess';

our $VERSION = "1.003";

sub columns {
  return qw/id parentid displayOrder title titleImage body
    thumbImage thumbWidth thumbHeight imagePos
    release expire keyword template link admin threshold
    summaryLength generator level listed lastModified flags
    customDate1 customDate2 customStr1 customStr2
    customInt1 customInt2 customInt3 customInt4 
    lastModifiedBy created createdBy author pageTitle
    force_dynamic cached_dynamic inherit_siteuser_rights
    metaDescription metaKeywords summary menu titleAlias linkAlias/;
}

sub table {
  'article';
}

sub numeric {
  qw(id listed parentid threshold summaryLength level 
     customInt1 customInt2 customInt3 customInt4 menu);
}

sub section {
  my ($self) = @_;

  my $section = $self;
  while ($section->{parentid} > 0
	 and my $parent = Articles->getByPkey($section->{parentid})) {
    $section = $parent;
  }

  return $section;
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

  if (!$dynamic && $self->generator =~ /\bCatalog\b/) {
    require Products;
    my @tiers = Products->pricing_tiers;
    @tiers and $dynamic = 1;
  }

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

  $cfg ||= BSE::Cfg->single;

  defined $link or $link = $self->{link};

  length $link or return;

  my $filename = $link;
  $filename =~ s!/\w*$!!;
  $filename =~ s{^\w+://[\w.-]+(?::\d+)?}{};
  $filename = $cfg->content_base_path() . $filename;
  $filename =~ s!//+!/!;
  
  return $filename;
}

sub cached_filename {
  my ($self, $cfg) = @_;

  $cfg ||= BSE::Cfg->single;

  my $dynamic_path = $cfg->entryVar('paths', 'dynamic_cache');
  return $dynamic_path . "/" . $self->{id} . ".html";
}

sub html_filename {
  my ($self, $cfg) = @_;

  $cfg ||= BSE::Cfg->single;

  return $self->is_dynamic
    ? $self->cached_filename($cfg)
      : $self->link_to_filename($cfg);
}

sub remove_html {
  my ($self, $cfg) = @_;

  my $filename = $self->html_filename($cfg)
    or return 1;

  unlink $filename
    or return;

  return 1;
}

sub remove {
  my ($self, $cfg) = @_;

  $cfg or confess "No \$cfg supplied to ", ref $self, "->remove";

  $self->remove_images($cfg);

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
  $self->remove_html($cfg);
  
  $self->SUPER::remove();
}

sub all_parents {
  my ($self) = @_;

  my @result = $self->step_parents;
  if ($self->{parentid} > 0 && !grep $_->{id} eq $self->{parentid}, @result) {
    push @result, $self->parent;
  }

  return @result;
}

sub is_step_ancestor {
  my ($self, $other, $max) = @_;

  my $other_id = ref $other ? $other->{id} : $other;
  my %seen;

  $max ||= 10;

  # early exit if possible
  return 1 if $self->{parentid} == $other_id;

  my @all_parents = $self->all_parents;
  return 1 if grep $_->{id} == $other_id, @all_parents;
  my @work = map [ 0, $_], grep !$seen{$_}++, @all_parents;
  while (@work) {
    my $entry = shift @work;
    my ($level, $workart) = @$entry;

    $level++;
    if ($level < $max) {
      @all_parents = $workart->all_parents;
      return 1 if grep $_->{id} == $other_id, @all_parents;
      push @work, map [ $level, $_ ], grep !$seen{$_}++, @all_parents;
    }
  }

  return 0;
}

sub possible_stepparents {
  my $self = shift;

  return BSE::DB->query(articlePossibleStepparents => $self->{id}, $self->{id});
}

sub possible_stepchildren {
  my $self = shift;

  return BSE::DB->query(articlePossibleStepchildren => $self->{id}, $self->{id});
}

sub link {
  my ($self, $cfg) = @_;

  if ($self->flags =~ /P/) {
    my $parent = $self->parent;
    $parent and return $parent->link($cfg);
  }

  $self->is_linked
    or return "";

  $cfg ||= BSE::Cfg->single;

  if ($self->{linkAlias} && $cfg->entry('basic', 'use_alias', 1)) {
    my $prefix = $cfg->entry('basic', 'alias_prefix', '');
    my $link = $prefix . '/' . $self->{linkAlias};
    if ($cfg->entry('basic', 'alias_suffix', 1)) {
      my $title = $self->{title};
      $title =~ tr/a-zA-Z0-9/_/cs;
      $link .= '/' . $title;
    }
    return $link;
  }
  else {
    return $self->{link};
  }
}

sub is_linked {
  my ($self) = @_;

  return $self->flags !~ /D/;
}

1;
