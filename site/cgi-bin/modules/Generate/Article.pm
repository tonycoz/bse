package Generate::Article;
use strict;
use BSE::Template;
use Constants qw(%LEVEL_DEFAULTS $CGI_URI $ADMIN_URI $IMAGES_URI 
                 $UNLISTED_LEVEL1_IN_CRUMBS);
use Images;
use vars qw(@ISA);
use Generate;
use Util qw(generate_button);
use BSE::Util::Tags;
use ArticleFiles;
@ISA = qw/Generate/;
use DevHelp::HTML;

my $excerptSize = 300;

my %level_names = map { $_, $LEVEL_DEFAULTS{$_}{display} }
  grep { $LEVEL_DEFAULTS{$_}{display} } keys %LEVEL_DEFAULTS;

sub edit_link {
  my ($self, $id) = @_;
  return "$CGI_URI/admin/add.pl?id=$id";
}

sub make_article_body {
  my ($self, $acts, $articles, $article, $auto_images, @images) = @_;

  return $self->format_body($acts, $articles, @$article{qw/body imagePos/}, 
			    $auto_images, @images);
}

sub link_to_form {
  my ($self, $link, $text, $target) = @_;

  my ($url, $query) = split /\?/, $link;
  my $form = qq!<form action="$url"!;
  $form .= qq! target="$target"! if $target;
  $form .= '>';
  if (defined $query && length $query) {
    for my $attr (split /&/, $query) {
      my ($name, $value) = split /=/, $attr, 2;
      # I'm assuming none of the values are uri escaped
      $value = escape_html($value);
      $form .= qq!<input type=hidden name="$name" value="$value">!
    }
  }
  $form .= qq!<input type=submit value="!.escape_html($text).'">';
  $form .= "</form>";

  return $form;
}

sub generate_low {
  my ($self, $template, $article, $articles, $embedded) = @_;
  my %acts;
  %acts = $self -> baseActs($articles, \%acts, $article, $embedded);

  return BSE::Template->replace($template, $self->{cfg}, \%acts);
}

sub tag_title {
  my ($article, $images, $args, $acts, $funcname, $templater) = @_;

  my $which = $args || 'article';

  exists $acts->{$which} 
    or return "** no such object $which **";

  my $title = $acts->{$which}->('title');
  my $imagename = $which eq 'article' ? $article->{titleImage} : 
    $acts->{$which}->('titleImage');
  $imagename and
    return qq!<img src="/images/titles/$imagename"!
      .qq! border="0" alt="$title" />! ;
  my $im;
  if ($which eq 'article') {
    ($im) = grep lc $_->{name} eq 'bse_title', @$images;
  }
  else {
    my $id = $acts->{$which}->('id');
    require Images;
    my @images = Images->getBy(articleId=>$id);
    ($im) = grep lc $_->{name} eq 'bse_title', @$images;
  }

  if ($im) {
    return qq!<img src="/images/$im->{image}" width="$im->{width}"!
      . qq! height="$im->{height}" alt="$title" />!;
  }
  else {
    return $title;
  }
}

sub baseActs {
  my ($self, $articles, $acts, $article, $embedded) = @_;

  # used to generate the list (or not) of children to this article
  my $child_index = -1;
  my @children = $articles->listedChildren($article->{id});

  # used to generate a navigation list for the article
  # generate a list of ancester articles/sections
  # Jason calls these breadcrumbs
  my @crumbs;
  my @ancestors;
  my $temp = $article;
  while ($temp->{parentid} > 0
	and my $crumb = $articles->getByPkey($temp->{parentid})) {
    unshift(@ancestors, $crumb);
    unshift(@crumbs, $crumb) if $crumb->{listed} == 1 || $crumb->{level} == 1;
    $temp = $crumb;
  }
  my $crumb_index = -1;
  my @work_crumbs; # set by the crumbs iterator

  my $parent = $articles->getByPkey($article->{parentid});
  my $section = $crumbs[0];

  my @images = Images->getBy('articleId', $article->{id});
  my $image_index = -1;
  my $had_image_tags = 0;
  my @files = sort { $b->{displayOrder} <=> $a->{displayOrder} }
    ArticleFiles->getBy(articleId=>$article->{id});
  
  my $blank = qq!<img src="$IMAGES_URI/trans_pixel.gif"  width="17" height="13" border="0" align="absbottom" alt="" />!;

  my @stepkids;
  my @allkids;
  my @stepparents;
  if (UNIVERSAL::isa($article, 'Article')) {
    @stepkids	  = $article->visible_stepkids;
    @allkids	  = $article->all_visible_kids;
    @stepparents  = $article->step_parents;
  }
  my $allkids_index;
  # separate these so the closures can see %acts
  my %acts =
    (
     $self->SUPER::baseActs($articles, $acts, $article, $embedded),
     article=>sub { escape_html($article->{$_[0]}) },
     ifTitleImage => 
     sub { 
       my $which = shift || 'article';
       return $acts->{$which} && $acts->{$which}->('titleImage')
     },
     title => [ \&tag_title, $article, \@images ],
     thumbnail =>
     sub {
       my ($which, $class) = split ' ', $_[0];
       $which ||= 'article';
       if ($acts->{$which} && $acts->{$which}->('thumbImage')) {
         my $result = '<img src="/images/'.$acts->{$which}->('thumbImage')
           .'" width="'.$acts->{$which}->('thumbWidth')
             .'" height="'.$acts->{$which}->('thumbHeight').'"';
         $result .= qq! class="$class"! if $class;
         $result .= ' border="0" />';
         return $result;
       }
       else {
         return '';
       }
     },
     ifThumbnail =>
     sub {
       my $which = shift || 'article';
       return $acts->{$which} && $acts->{$which}->('thumbImage');
     },
     ifUnderThreshold => 
     sub { 
       if ($article->{threshold} !~ /\d/) {
	 use Data::Dumper;
	 use Carp qw/cluck/;
	 print STDERR Dumper($article);
	 cluck 'Why is a template name in \$article->{threshold}?';
       }

       my $count;
       my $what = $_[0] || '';
       if ($what eq 'stepkids') {
	 $count = @stepkids;
       }
       elsif ($what eq 'allkids') {
	 $count = @allkids;
       }
       else {
	 $count = @children;
       }
       $count <= $article->{threshold};
     },
     ifChildren => sub { scalar @children },
     iterate_children_reset => sub { $child_index = -1; },
     iterate_children =>
     sub {
       return ++$child_index < @children;
     },
     child =>
     sub {
       return escape_html($children[$child_index]{$_[0]});
     },

     section=>sub { escape_html($section->{$_[0]}) },

     # these are mostly obsolete, use moveUp and moveDown instead
     # where possible
     ifPrevChild => sub { $child_index > 0 },
     ifNextChild => sub { $child_index < $#children },

     # generate buttons for administration (only for admin generation)
     admin=>
     sub {
       if ($self->{admin} && $self->{request}) {
	 my $req = $self->{request};
         my $html = <<HTML;
<table><tr>
<td><form action="$CGI_URI/admin/add.pl">
<input type=submit value="Edit $level_names{$article->{level}}">
<input type=hidden name=id value="$article->{id}">
</form></td>
<td><form action="$ADMIN_URI">
<input type=submit value="Admin menu">
</form></td>
HTML
         if (exists $level_names{1+$article->{level}}
	     && $req->user_can(edit_add_child=>$article)) {
           $html .= <<HTML;
<td><form action="$CGI_URI/admin/add.pl">
<input type=submit value="Add $level_names{1+$article->{level}}">
<input type=hidden name=parentid value="$article->{id}">
</form></td>
HTML
	 }
	 if (generate_button() && $req->user_can(regen_article=>$article)) {
	   $html .= <<HTML;
<td><form action="$CGI_URI/admin/generate.pl">
<input type=hidden name=id value="$article->{id}">
<input type=submit value="Regenerate">
</form></td>
HTML
	 }
	 $html .= "<td>".$self->link_to_form($article->{admin}."&admin=0",
					     "Display", "_blank")."</td>";
	 if ($article->{link}) {
	   $html .= "<td>"
	     . $self->link_to_form($article->{link}, "On site", "_blank")
	       . "</td>";
	 } elsif ($parent && $parent->{link}) {
	   $html .= "<td>"
	     . $self->link_to_form($parent->{link}, "On site", "_blank")
	       . "</td>";
	 }
         if ($parent && $parent->{admin} ne $article->{admin} && !$embedded) {
           $html .= "<td>"
             .$self->link_to_form($parent->{admin}, "Parent")."</td>";
         }
         $html .= <<HTML;
</tr></table>
HTML
         return $html;
       } else {
         return '';
       }
     },

     # transform the article or response body (entities, images)
     body=>sub {
       return $self->make_article_body($acts, $articles, $article,
				       !$had_image_tags, @images);
     },

     # used to display a navigation path of parent sections
     iterate_crumbs_reset => 
     sub {
       my $args = $_[0];
       $args ||= $UNLISTED_LEVEL1_IN_CRUMBS ? 'showtop' : 'listedonly';
       if ($args eq 'showtop') {
	 @work_crumbs = @crumbs;
       }
       else {
	 @work_crumbs = grep $_->{listed}, @crumbs;
       }
       $crumb_index = -1;
     },
     iterate_crumbs =>
     sub {
       return ++$crumb_index < @work_crumbs;
     },
     crumbs =>
     sub {
       # obsolete me
       return escape_html($work_crumbs[$crumb_index]{$_[0]});
     },
     crumb =>
     sub {
       return escape_html($work_crumbs[$crumb_index]{$_[0]});
     },
     ifCrumbs =>
     sub {
       my $args = $_[0];
       $args ||= $UNLISTED_LEVEL1_IN_CRUMBS ? 'showtop' : 'listedonly';

       my @temp;
       if ($args eq 'showtop') {
	 return scalar @crumbs;
       }
       else {
	 return scalar grep $_->{listed}, @crumbs;
       }
     },

     # access to parent
     ifParent => sub { $parent },
     parent =>
     sub { return $parent && escape_html($parent->{$_[0]}) },
     # for rearranging order in admin mode
     moveDown=>
     sub {
       @children > 1 or return '';
       if ($self->{admin} && $child_index < $#children) {
         my $html = <<HTML;
<a href="$CGI_URI/admin/move.pl?id=$children[$child_index]{id}&d=down"><img src="$IMAGES_URI/admin/move_down.gif" width="17" height="13" border="0" alt="Move Down" align="absbottom" /></a>
HTML
	 chop $html;
	 return $html;
       } else {
         return $blank;
       }
     },
     moveUp=>
     sub {
       @children > 1 or return '';
       if ($self->{admin} && $child_index > 0) {
         my $html = <<HTML;
<a href="$CGI_URI/admin/move.pl?id=$children[$child_index]{id}&d=up"><img src="$IMAGES_URI/admin/move_up.gif" width="17" height="13" border="0" alt="Move Up" align="absbottom" /></a>
HTML
	 chop $html;
	 return $html;
       } else {
         return $blank;
       }
     },
     movestepkid =>
     sub {
       my ($arg, $acts, $funcname, $templater) = @_;
       my $html = '';
       return '' unless $self->{admin};
       return '' unless @allkids > 1;
       my ($img_prefix, $urladd) = 
	 DevHelp::Tags->get_parms($arg, $acts, $templater);
       $img_prefix = '' unless defined $img_prefix;
       $urladd = '' unless defined $urladd;
       my $refreshto = escape_uri($ENV{SCRIPT_NAME} . "?id=$article->{id}$urladd");
       if ($allkids_index < $#allkids) {
	 $html .= <<HTML
<a href="$CGI_URI/admin/move.pl?stepparent=$article->{id}&d=swap&id=$allkids[$allkids_index]{id}&other=$allkids[$allkids_index+1]{id}&refreshto=$refreshto"><img src="$IMAGES_URI/admin/${img_prefix}move_down.gif" width="17" height="13" border="0" alt="Move Down" align="absbottom" /></a>
HTML
       }
       else {
	 $html .= $blank;
       }
       if ($allkids_index > 0) {
	 $html .= <<HTML
<a href="$CGI_URI/admin/move.pl?stepparent=$article->{id}&d=swap&id=$allkids[$allkids_index]{id}&other=$allkids[$allkids_index-1]{id}&refreshto=$refreshto"><img src="$IMAGES_URI/admin/${img_prefix}move_up.gif" width="17" height="13" border="0" alt="Move Up" align="absbottom" /></a>
HTML
       }
       else {
	 $html .= $blank;
       }
       $html =~ tr/\n//d;
       return $html;
     },
     ifCurrentPage=>
     sub {
       my $arg = shift;
       $arg && $acts->{$arg} && $acts->{$arg}->('id') == $article->{id};
     },
     ifAncestor =>
     sub {
       my ($arg, $acts, $name, $templater) = @_;
       unless ($arg =~ /^\d+$/) {
	 $arg = $acts->{$arg} && $templater->perform($acts, $arg, 'id')
	   or return;
       }
       scalar grep $_->{id} == $arg, @ancestors, $article;
     },
     
     # access to images, if any
     iterate_images_reset => sub { $image_index = -1 },
     iterate_images => sub { $had_image_tags = 1; ++$image_index < @images },
     image =>
     sub {
       my ($which, $align, $rest) = split ' ', $_[0], 3;

       $had_image_tags = 1;
       my $im;
       if (defined $which && $which =~ /^\d+$/ && $which >=1 
	   && $which <= @images) {
	 $im = $images[$which-1];
       }
       else {
	 $im = $images[$image_index];
       }

       return $self->_format_image($im, $align, $rest);
     },
     imagen => 
     sub {
       my ($name, $align, $rest) = split ' ', $_[0], 3;

       $had_image_tags = 1;
       my ($im) = grep lc $name eq lc $_->{name}, @images
	 or return '';

       $self->_format_image($im, $align, $rest);
     },
     ifImage => sub { $_[0] >= 1 && $_[0] <= @images },
     ifImages => sub { @images },
     BSE::Util::Tags->make_iterator(\@files, 'file', 'files'),
     BSE::Util::Tags->make_iterator(\@stepkids, 'stepkid', 'stepkids'),
     BSE::Util::Tags->make_iterator(\@allkids, 'allkid', 'allkids', \$allkids_index),
     BSE::Util::Tags->make_iterator(\@stepparents, 'stepparent', 'stepparents'),
    );

  if ($article->{link} =~ /^\w+:/) {
    my $oldurl = $acts{url};
    my $cfg = $self->{cfg} || BSE::Cfg->new;
    my $urlbase = $cfg->entryErr('site', 'url');
    $acts{url} =
      sub {
        my $value = $oldurl->(@_);
        unless ($value =~ /^\w+:/) {
          # put in the base site url
          $value = $urlbase . $value;
        }
        return $value;
      };
  }
  return %acts;
}

sub generate {
  my ($self, $article, $articles) = @_;

  my $html = BSE::Template->get_source($article->{template}, $self->{cfg});
  $html =~ s/<:\s*embed\s+(?:start|end)\s*:>//g;

  return $self->generate_low($html, $article, $articles, 0);
}

1;

__END__

=head1 NAME

  Generate::Article - generates articles.

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 TAGS


=head2 Tag notes

In your HTML each tag will be preceded by <: and followed by :>

Tags marked as conditional will require a little more.  Conditional
tags can be used in two ways:

<:ifName args:>true text<:or:>false text<:eif:>

or:

<:if Name args:>true text<:or Name:>false text<:eif Name:>

Tags starting iterator ... are used as iterators, like:

<:iterator begin name:>
repeated text
<:iterator separator name:>
separator text
<:iterator end name:>

In general, a parameter I<which> can be any one of 'article', 'parent'
or 'section'.  In a child iterator it can also be 'child'.  In a
crumbs iterator it can also be 'crumbs'.  If I<which> is missing it
means the current article.

=head2 Normal tags

=over 4

=item article I<name>

Access to fields of the article. See L<Article attributes>.

=item parent I<name>

Access to fields of the parent article. See L<Article attributes>.

=item ifParent

Conditional tag, true if there is a parent.

=item section I<name>

Access to the fields of the section containing the article.  See
L<Article attributes>.

=item title I<which>

The title of the article presented as an image if there is a
titleImage or as text.  See L<Tag notes> for values for which.

=item ifTitleImage I<which>

Conditional tag, true if the given article has a titleImage,

=item thumbnail I<which> I<class>

The thumbnail image as an <img> tag for object I<which> where I<which>
is one of the article objects defined.  The optional I<class> adds a
class attribute to the tag with that class.

=item ifThumbnail I<which>

Conditional tag, true if the article specified by I<which> has a
thumbnail.

=item ifUnderThreshold

=item ifUnderThreshold stepkids

=item ifUnderThreshold allkids

Conditional tag, true if the number of children/stepkids/allkids is
less or equal to the article's threshold.

=item body

The formatted body of the article.

=item keywords

Ignore this one.

=item iterator ... crumbs [option]

Iterates over the ancestors of the article.  See the L</item crumbs>.

I<option> can be empty, "listedonly" or "showtop".  If empty the
display of an unlisted level1 ancestor is controlled by
$UNLISTED_LEVEL1_IN_CRUMBS, if "listedonly" then an unlisted level1
article isn't shown in the crumbs, and it is if "showtop" is the
I<option>.  This can be used in <: ifCrumbs :> too.

=item crumbs I<name>

Access to the fields of the specific ancestor.  I<name> can be any of
the L<Article attributes>.

=item ifCrumbs [options]

Conditional tag, true if there are any crumbs.

See L</iterator ... crumbs [option]> for information on I<option>.

=item ifChildren

Conditional tag, true if the article has any children.

=item iterator ... children

Iterates over the children of the article.  See the L</item child>.

=item child I<name>

Access to the fields of the current child.

=item summary

Produces a processed summary of the current child's body.

=item ifPrevChild

Conditional tag, true if there is a previous child.  Originally used
for generating a move up link, but you can use the moveUp tag for
that now.

=item ifNextChild

Conditional tag, true if there is a next child.  Originally used to
generating a move down link, but you can use the moveDown tag for that
now.

=item ifCurrentPage I<which>

Conditional tag, true if the given I<which> is the page currently
being generated.  This can be used to apply special formatting if a
C<level1> or C<level2> article is the current page.

=item iterator ... images

Iterates over the images for the given article.

=item image which field

Extracts the given field from the specified image.

I<which> in this can be either an image index to access a specific
image, or "-" to access the current image in the images iterator.

The image fields are:

=over

=item articleId

The identifier of the article the image belongs to.

=item image

A partial url of the image, relative to /images/.

=item alt

Alternative text of the image.

=item width

=item height

dimensions of the image.

=item url

the url if any associated with the image

=back

=item image which align

=item image which

=item image

Produces HTML to render the given image.

I<which> can be an image index (1, 2, 3...) to select one of the
images from the current article, or '-' or omitted to select the
current image from the images iterator.  If align is present then the
C<align> attribute of the image is set.

If the image has a URL that <a href="...">...</a> will also be
generated.

=item ifImage imageindex

Condition tag, true if an image exists at the given index.

=item ifImages

Conditional tag, true if the article has any images.

=item embed child

This has been made more general and been moved, see L<Generate/embed child>.

=back

=head2 Article attributes

=over 4

=item id

Identifies the article.

=item parentId

The identifier of the parent article.

=item title

The title of the article.  See the title tag

=item titleImage

The name of the title image for the article, if any.  See the title
and ifTitleImage tags.

=item body

The body of the article.  See the body tag.

=item thumbImage

=item thumbWidth

=item thumbHeight

The thumbnail image for the article, if any.  See the thumbnail tag.

=item release

=item expire

The release and expiry dates of the article.

=item keyword

Any keywords for the article.  Indexed by the search engine.

=item link

=item admin

Links to the normal and adminstrative versions of the article.  The
url tag defined by Generate.pm will select the appropriate tag for the
current mode.

=item threshold

The maximum number of articles that should be embeded into the current
article for display.  See the ifUnderThreshold tag.

=item summaryLength

The maximum amount of text displayed in the summary of an article.
See the summary tag.

=item generator

The class used to generate the article.  Should be one of
Generate::Article, Generate::Catalog or Generate::Product.

=item level

The level of the article.  Sections are level1, etc

=item listed

How the article is listed.  If zero then the article can only be found
in a search.  If 1 then the article is listed in menus and article
contents, if 2 then the article is only listed in article contents.

=item lastModified

When the article was last modified.  Currently only used for display
in search results.

=back

The following attributes are unlikely to be used in a page:

=over 4

=item displayOrder

Used internally to control the ordering of articles within a section.

=item imagePos

The position of the first image in the body.  The body tag will format
images into the body as specified by this tag.

=item template

The template used to format the article.

=back

=head2 Admin tags

=over 4

The following tags produce output only in admin mode.

=item admin

Produces buttons and links used for administering the article.

=item moveUp

Generates a move up link if there is a previous child for the current
child.

=item moveDown

Generates a move down link if there is a next child for the current child.


=back

=cut

