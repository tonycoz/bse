package BSE::TB::Article;
use strict;
# represents an article from the database
use Squirrel::Row;
use BSE::TB::SiteCommon;
use BSE::TB::TagOwner;
use vars qw/@ISA/;
@ISA = qw/Squirrel::Row BSE::TB::SiteCommon BSE::TB::TagOwner/;
use Carp 'confess';

our $VERSION = "1.025";

=head1 NAME

Article - article objects for BSE.

=head1 SYNOPSIS

  use BSE::API qw(bse_make_article);

  my $article = bse_make_article(...)

  my $article = BSE::TB::Articles->getByPkey($id);

=head1 DESCRIPTION

Implements the base article object for BSE.

=head1 USEFUL METHODS

=over

=cut

sub columns {
  return qw/id parentid displayOrder title titleImage body
    thumbImage thumbWidth thumbHeight imagePos
    release expire keyword template link admin threshold
    summaryLength generator level listed lastModified flags
    customDate1 customDate2 customStr1 customStr2
    customInt1 customInt2 customInt3 customInt4 
    lastModifiedBy created createdBy author pageTitle
    force_dynamic cached_dynamic inherit_siteuser_rights
    metaDescription metaKeywords summary menu titleAlias linkAlias
    category/;
}

sub db_columns {
  my ($self) = @_;

  return map { $_ eq "summary" ? "summaryx" : $_ } $self->columns;
}

=item id

=item parentid

=item displayOrder

=item title

=item titleImage

=item body

=item thumbImage

=item thumbWidth

=item thumbHeight

=item imagePos

=item release

=item expire

=item keyword

=item template

=item threshold

=item summaryLength

=item generator

=item level

=item listed

=item lastModified

=item flags

=item customDate1

=item customDate2

=item customStr1

=item customStr2

=item customInt1

=item customInt2

=item customInt3

=item customInt4

=item lastModifiedBy

=item created

=item createdBy

=item author

=item pageTitle

=item force_dynamic

=item cached_dynamic

=item inherit_siteuser_rights

=item metaDescription

=item metaKeywords

=item summary

=item menu

=item titleAlias

=item linkAlias

=item category

Simple column accessors.

=cut

sub table {
  'article';
}

sub numeric {
  qw(id listed parentid threshold summaryLength level 
     customInt1 customInt2 customInt3 customInt4 menu);
}

=item section

Return the article's section.

=cut

sub section {
  my ($self) = @_;

  my $section = $self;
  while ($section->{parentid} > 0
	 and my $parent = $section->parent) {
    $section = $parent;
  }

  return $section;
}

=item parent

Return the article's parent.

=cut

sub parent {
  my ($self) = @_;

  my $parentid = $self->parentid;

  $parentid == -1
    and return;
  $self->{_parent} && $self->{_parent}->id == $parentid
    and return $self->{_parent};
  return ($self->{_parent} = BSE::TB::Articles->getByPkey($self->{parentid}));
}

sub update_dynamic {
  my ($self, $cfg) = @_;

  $cfg && $cfg->can('entry')
    or confess 'update_dynamic called without $cfg';

  # conditional in case something strange is in the config file
  my $dynamic = $cfg->entry('basic', 'all_dynamic', 0) ? 1 : 0;

  if (!$dynamic && $self->generator =~ /\bCatalog\b/) {
    require BSE::TB::Products;
    my @tiers = BSE::TB::Products->pricing_tiers;
    @tiers and $dynamic = 1;
  }

  $dynamic or $dynamic = $self->{force_dynamic};

  $dynamic or $dynamic = $self->is_access_controlled;

  $dynamic or $dynamic = $self->force_dynamic_inherited;

  $self->{cached_dynamic} = $dynamic;
}

=item is_dynamic

Return true if the article is rendered dynamically.

=cut

sub is_dynamic {
  $_[0]{cached_dynamic};
}

=item is_accessible_to($group)

Return true if the article is accessible to the supplied siteuser
group or group id.

=cut

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

=item is_access_controlled

Return true if the article is access controlled.

=cut

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

  # remove any appended title,
  $filename =~ s!(.)/\w+$!$1!;
  $filename =~ s{^\w+://[\w.-]+(?::\d+)?}{};
  $filename = $cfg->content_base_path() . $filename;
  if ($filename =~ m(/$)) {
    $filename .= $cfg->entry("basic", "index_file", "index.html");
  }
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

  $self->remove_tags;

  $self->remove_images($cfg);

  $self->remove_files($cfg);
  
  # remove any step(child|parent) links
  require OtherParents;
  my @steprels = OtherParents->anylinks($self->{id});
  for my $link (@steprels) {
    $link->remove();
  }

  # remove any site user access controls
  BSE::DB->single->run(bseRemoveArticleSiteUserGroups => $self->id);

  # remove any admin user/group access controls
  BSE::DB->single->run(bseRemoveArticleAdminAccess => $self->id);

  # remove the static page
  $self->remove_html($cfg);

  $self->SUPER::remove();
}

=item all_parents

Return a list of all parents.

=cut

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

  unless ($self->{linkAlias} && $cfg->entry('basic', 'use_alias', 1)) {
    return $self->{link};
  }

  my $prefix = $cfg->entry('basic', 'alias_prefix', '');
  my $link;
  if ($cfg->entry('basic', 'alias_recursive')) {
    my @steps = $self->{linkAlias};
    my $article = $self;
    while ($article = $article->parent) {
      if ($article->{linkAlias}) {
	unshift @steps, $article->{linkAlias};
      }
    }
    $link = join('/', $prefix, @steps);
  }
  else {
    $link = $prefix . '/' . $self->{linkAlias};
  }
  if ($cfg->entry('basic', 'alias_suffix', 1)) {
    my $title = $self->{title};
    $title =~ tr/a-zA-Z0-9/-/cs;
    $link .= '/' . $title;
  }
  return $link;
}

=item admin

Return the admin link for the article.

=cut

sub admin {
  my ($self) = @_;

  return BSE::Cfg->single->admin_url("admin", { id => $self->id });
}

=item is_linked

Return true if the article can be linked to.

=cut

sub is_linked {
  my ($self) = @_;

  return $self->flags !~ /D/;
}

sub tag_owner_type {
  return "BA";
}

# the time used for expiry/release comparisons
sub _expire_release_datetime {
  my ($year, $month, $day) = (localtime)[5,4,3];
  my $today = sprintf("%04d-%02d-%02d 00:00:00ZZZ", $year+1900, $month+1, $day);
}

=item is_expired

Returns true if the article expiry date has passed.

=cut

sub is_expired {
  my $self = shift;

  return $self->expire lt _expire_release_datetime();
}

=item is_released

Returns true if the article release date has passed (ie. the article
has been released.)

=cut

sub is_released {
  my $self = shift;

  return $self->release le _expire_release_datetime();
}

=item listed_in_menu

Return true if the article should be listed in menus.

=cut

sub listed_in_menu {
  my $self = shift;

  return $self->listed == 1;
}

=item ancestors

Returns a list of ancestors of self.

=cut

sub ancestors {
  my ($self) = @_;

  unless ($self->{_ancestors}) {
    my @ancestors;
    my $work = $self;
    while ($work->parentid != -1) {
      $work = $work->parent;
      push @ancestors, $work;
    }

    $self->{_ancestors} = \@ancestors;
  }

  return @{$self->{_ancestors}};
}

=item is_descendant_of($ancestor)

Return true if self is a decsendant of the supplied article or article
id.

=cut

sub is_descendant_of {
  my ($self, $ancestor) = @_;

  my $ancestor_id = ref $ancestor ? $ancestor->id : $ancestor;

  for my $anc ($self->ancestors) {
    return 1 if $anc->id == $ancestor_id;
  }

  return 0;
}

=item visible_ancestors

Returns all visible ancestors.

Lists the top-level ancestor C<last>.

This list does not include the article itself.

=cut

sub visible_ancestors {
  my ($self) = @_;

  return grep $_->listed, $self->ancestors;
}

=item menu_ancestors

Returns visible ancestprs that are visible for menus (ie. listed = 1).

Lists the top-level ancestor C<last>.

This list does not include the article itself.

=cut

sub menu_ancestors {
  my ($self) = @_;

  return grep $_->listed, $self->ancestors;
}

=item should_generate

Return true if this article should have pages generated, either for
static content or for dynamic.

=cut

sub should_generate {
  my ($self) = @_;

  return $self->is_linked && $self->listed && $self->is_released && !$self->is_expired;
}

=item should_index

Returns true if the article should be indexed.

=cut

sub should_index {
  my ($self) = @_;

  return ($self->listed || $self->is_index_even_if_hidden)
    && $self->is_linked
      && !$self->is_dont_index
	&& !$self->is_dont_index_or_kids
}

=item is_index_even_if_hidden

Return true if the article's index even if hidden flag is set.

=cut

sub is_index_even_if_hidden {
  my ($self) = @_;

  return $self->flags =~ /I/;
}

=item is_dont_index

Return true if the "don't index" flag (C<N>) is set.

=cut

sub is_dont_index {
  return $_[0]->flags =~ /N/;
}

=item is_dont_index_or_kids

Return true if the article or any of it's parents have the "don't
index me or my children" flag (C<C>) set.

=cut

sub is_dont_index_or_kids {
  my ($self) = @_;

  $self->flags =~ /C/ and return 1;

  my $parent = $self->parent
    or return 0;

  return $parent->is_dont_index_or_kids;
}

sub restricted_method {
  my ($self, $name) = @_;

  return $self->SUPER::restricted_method($name)
    || $name =~ /^(?:update_|remove_|add_|mark_modified)/;
}

sub tableClass {
  return "BSE::TB::Articles";
}

=item mark_modified

Call by admin code to do the things we do when an article is modified.

Parameters:

=over

=item *

actor - an audit log compatible actor.

=back

=cut

sub mark_modified {
  my ($self, %opts) = @_;

  require BSE::Util::SQL;
  $self->set_lastModified(BSE::Util::SQL::now_sqldatetime());
  $self->set_lastModifiedBy(ref $opts{actor} ? $opts{actor}->logon : "");
}

=item uncache

Free any cached data.

=cut

sub uncache {
  my ($self) = @_;

  delete @{$self}{qw/_parent/};

  $self->SUPER::uncache();
}

1;

__END__

=back

=head1 BASE CLASSES

L<BSE::TB::SiteCommon>

L<BSE::TB::TagOwner>

L<Squirrel::Row>

=head1 AUTHOR

Tony Cook <tony@develop-help.com>

=cut
