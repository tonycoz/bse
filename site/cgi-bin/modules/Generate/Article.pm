package Generate::Article;
use strict;
use BSE::Template;
use Constants qw(%LEVEL_DEFAULTS $CGI_URI $ADMIN_URI $IMAGES_URI 
                 $UNLISTED_LEVEL1_IN_CRUMBS);
use Images;
use vars qw(@ISA);
use Generate;
use Util qw(generate_button);
use BSE::Util::Tags qw(tag_article);
use ArticleFiles;
@ISA = qw/Generate/;
use DevHelp::HTML;
use BSE::Arrows;
use Carp 'confess';
use BSE::Util::Iterate;

my $excerptSize = 300;

my %level_names = map { $_, $LEVEL_DEFAULTS{$_}{display} }
  grep { $LEVEL_DEFAULTS{$_}{display} } keys %LEVEL_DEFAULTS;

sub new {
  my ($class, %opts) = @_;

  $opts{top} or confess "Please supply 'top' to $class->new";

  return $class->SUPER::new(%opts);
}

sub edit_link {
  my ($self, $id) = @_;
  return "$CGI_URI/admin/add.pl?id=$id";
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
      $form .= qq!<input type=hidden name="$name" value="$value" />!
    }
  }
  $form .= qq!<input type=submit value="!.escape_html($text).'" />';
  $form .= "</form>";

  return $form;
}

sub generate_low {
  my ($self, $template, $article, $articles, $embedded) = @_;
  my %acts;
  %acts = $self -> baseActs($articles, \%acts, $article, $embedded);

  my $page = BSE::Template->replace($template, $self->{cfg}, \%acts);

  %acts = (); # try to destroy any circular refs

  return $page;
}

sub tag_title {
  my ($article, $images, $args, $acts, $funcname, $templater) = @_;

  my $which = $args || 'article';

  exists $acts->{$which} 
    or return "** no such object $which **";

  my $title = $templater->perform($acts, $which, 'title');
  my $imagename = $which eq 'article' ? $article->{titleImage} : 
    $templater->perform($acts, $which, 'titleImage');
  $imagename and
    return qq!<img src="/images/titles/$imagename"!
      .qq! border="0" alt="$title" />! ;
  my $im;
  if ($which eq 'article') {
    ($im) = grep lc $_->{name} eq 'bse_title', @$images;
  }
  else {
    my $id = $templater->perform($acts, $which, 'id');
    require Images;
    my @images = Images->getBy(articleId=>$id);
    ($im) = grep lc $_->{name} eq 'bse_title', @$images;
  }

  if ($im) {
    my $src = $im->{src} || "/images/$im->{image}";
    $src = escape_html($src);
    return qq!<img src="$src" width="$im->{width}"!
      . qq! height="$im->{height}" alt="$title" />!;
  }
  else {
    return $title;
  }
}

sub _default_admin {
  my ($self, $article, $embedded) = @_;

  my $req = $self->{request};
  my $html = <<HTML;
<table><tr>
<td><form action="$CGI_URI/admin/add.pl" name="edit">
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
<td><form action="$CGI_URI/admin/add.pl" name="addchild">
<input type=submit value="Add $level_names{1+$article->{level}}">
<input type=hidden name=parentid value="$article->{id}">
</form></td>
HTML
  }
  if (generate_button() && $req->user_can(regen_article=>$article)) {
    $html .= <<HTML;
<td><form action="$CGI_URI/admin/generate.pl" name="regen">
<input type=hidden name=id value="$article->{id}">
<input type=submit value="Regenerate">
</form></td>
HTML
  }
  $html .= "<td>".$self->link_to_form($article->{admin}."&admin=0",
				      "Display", "_blank")."</td>";
  my $parent = $article->parent;
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
}

sub abs_urls {
  my ($self, $article) = @_;

  my $top = $self->{top} || $article;

  $article->{link} =~ /^\w+:/ || $top->{link} =~ /^\w+:/;
}

sub tag_admin {
  my ($self, $article, $default, $embedded, $arg) = @_;

  $self->{admin} or return '';
  $self->{request} or return '';
  my $cfg = $self->{cfg};

  my $name = $arg || $default;
  my $template = "admin/adminmenu/$name";

  unless (BSE::Template->find_source($template, $cfg)) {
    return $self->_default_admin($article, $embedded);
  }

  my $parent = $article->parent;
  my %acts;
  %acts =
    (
     BSE::Util::Tags->static(\%acts, $cfg),
     BSE::Util::Tags->admin(\%acts, $cfg),
     BSE::Util::Tags->secure($self->{request}),
     article => [ \&tag_article, $article, $cfg ],
     parent => [ \&tag_article, $parent, $cfg ],
     ifParent => $parent,
     ifEmbedded => $embedded,
    );

  return BSE::Template->get_page($template, $cfg, \%acts);
}

sub tag_thumbimage {
  my ($self, $rcurrent, $images, $args) = @_;

  my ($geometry_id, $id, $field) = split ' ', $args;

  return $self->do_thumbimage($geometry_id, $id, $field, $images, $$rcurrent);
}

sub baseActs {
  my ($self, $articles, $acts, $article, $embedded) = @_;

  my $cfg = $self->{cfg} || BSE::Cfg->new;

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
  my $section = @crumbs ? $crumbs[0] : $article;

  my @images = Images->getBy('articleId', $article->{id});
  my @unnamed_images = grep $_->{name} eq '', @images;
  my @iter_images;
  my $image_index = -1;
  my $had_image_tags = 0;
  my @all_files = sort { $b->{displayOrder} <=> $a->{displayOrder} }
    ArticleFiles->getBy(articleId=>$article->{id});
  my @files = grep !$_->{hide_from_list}, @all_files;
  
  my $blank = qq!<img src="$IMAGES_URI/trans_pixel.gif"  width="17" height="13" border="0" align="absbottom" alt="" />!;

  my $top = $self->{top} || $article;
  my $abs_urls = $self->abs_urls($article);

  my $dynamic = $self->{force_dynamic}
    || (UNIVERSAL::isa($top, 'Article') ? $top->is_dynamic : 0);

  my @stepkids;
  my @allkids;
  my @stepparents;
  if (UNIVERSAL::isa($article, 'Article')) {
    @stepkids	  = $article->visible_stepkids;
    @allkids	  = $article->all_visible_kids;
    @stepparents  = $article->visible_step_parents;
  }
  my $allkids_index;
  my $current_image;
  my $art_it = BSE::Util::Iterate::Article->new(cfg =>$cfg);
  # separate these so the closures can see %acts
  my %acts =
    (
     $self->SUPER::baseActs($articles, $acts, $article, $embedded),
     article=>[ \&tag_article, $article, $cfg ],
     ifTitleImage => 
     sub { 
       my $which = shift || 'article';
       return $acts->{$which} && $acts->{$which}->('titleImage')
     },
     title => [ \&tag_title, $article, \@images ],
     thumbnail =>
     sub {
       my ($args, $acts, $name, $templater) = @_;
       my ($which, $class) = split ' ', $args;
       $which ||= 'article';
       if ($acts->{$which} && 
	   (my $image = $templater->perform($acts, $which, 'thumbImage'))) {
	 my $width = $templater->perform($acts, $which, 'thumbWidth');
	 my $height = $templater->perform($acts, $which, 'thumbHeight');
         my $result = '<img src="/images/'.$image
           .'" width="'.$width
             .'" height="'.$height.'"';
         $result .= qq! class="$class"! if $class;
         $result .= ' border="0" alt="" />';
         return $result;
       }
       else {
         return '';
       }
     },
     ifThumbnail =>
     sub {
       my ($which, $acts, $name, $templater) = @_;
       $which ||= 'article';
       return $acts->{$which} && 
	 $templater->perform($acts, $which, 'thumbImage');
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
       return tag_article($children[$child_index], $cfg, $_[0]);
     },

     section=> [ \&tag_article, $section, $cfg ],

     # these are mostly obsolete, use moveUp and moveDown instead
     # where possible
     ifPrevChild => sub { $child_index > 0 },
     ifNextChild => sub { $child_index < $#children },

     # generate buttons for administration (only for admin generation)
     admin=> [ tag_admin=>$self, $article, 'article', $embedded ],

     # transform the article or response body (entities, images)
     body=>sub {
       my ($args, $acts, $funcname, $templater) = @_;
       return $self->format_body(acts => $acts, 
				 article => $articles, 
				 text => $article->{body},
				 imagepos => $article->{imagePos}, 
				 abs_urls => $abs_urls,
				 auto_images => !$had_image_tags, 
				 templater => $templater, 
				 images => \@images,
				 files => \@all_files,
				 articles => $articles);
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
       return tag_article($work_crumbs[$crumb_index], $cfg, $_[0]);
     },
     crumb =>
     sub {
       return tag_article($work_crumbs[$crumb_index], $cfg, $_[0]);
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
     sub { return $parent && tag_article($parent, $cfg, $_[0]) },
     # for rearranging order in admin mode
     moveDown=>
     sub {
       @children > 1 or return '';
       if ($self->{admin} && $child_index < $#children) {
         my $html = <<HTML;
<a href="$CGI_URI/admin/move.pl?id=$children[$child_index]{id}&amp;d=down"><img src="$IMAGES_URI/admin/move_down.gif" width="17" height="13" border="0" alt="Move Down" align="bottom" /></a>
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
<a href="$CGI_URI/admin/move.pl?id=$children[$child_index]{id}&amp;d=up"><img src="$IMAGES_URI/admin/move_up.gif" width="17" height="13" border="0" alt="Move Up" align="bottom" /></a>
HTML
	 chop $html;
	 return $html;
       } else {
         return $blank;
       }
     },
     movekid => [ \&tag_movekid, $self, \$child_index, \@children, $article ],
     movestepkid =>
     sub {
       my ($arg, $acts, $funcname, $templater) = @_;
       my $html = '';
       return '' unless $self->{admin};
       return '' unless @allkids > 1;
       defined $allkids_index && $allkids_index >= 0 && $allkids_index < @allkids
	 or return '** movestepkid must be inside iterator allkids **';
       my ($img_prefix, $urladd) = 
	 DevHelp::Tags->get_parms($arg, $acts, $templater);
       $img_prefix = '' unless defined $img_prefix;
       $urladd = '' unless defined $urladd;
       my $top = $self->{top} || $article;
       my $refreshto = $ENV{SCRIPT_NAME} . "?id=$top->{id}$urladd";
       my $down_url = "";
       if ($allkids_index < $#allkids) {
	 $down_url = "$CGI_URI/admin/move.pl?stepparent=$article->{id}&d=swap&id=$allkids[$allkids_index]{id}&other=$allkids[$allkids_index+1]{id}";
       }
       my $up_url = "";
       if ($allkids_index > 0) {
	 $up_url = "$CGI_URI/admin/move.pl?stepparent=$article->{id}&d=swap&id=$allkids[$allkids_index]{id}&other=$allkids[$allkids_index-1]{id}";
       }
       
       return make_arrows($self->{cfg}, $down_url, $up_url, $refreshto, $img_prefix);
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
	 $acts->{$arg} or die "ENOIMPL\n";
	 $arg = $acts->{$arg} && $templater->perform($acts, $arg, 'id')
	   or return;
       }
       scalar grep $_->{id} == $arg, @ancestors, $article;
     },
     ifStepAncestor => [ \&tag_ifStepAncestor, $article ],
     # access to images, if any
     iterate_images_reset => 
     sub { 
       my ($arg) = @_;
       $image_index = -1;
       if ($arg eq 'all') {
	 @iter_images = @images;
       }
       elsif ($arg eq 'named') {
	 @iter_images = grep $_->{name} ne '', @images;
       }
       elsif ($arg =~ m!^named\s+/([^/]+)/$!) {
	 my $re = $1;
	 @iter_images = grep $_->{name} =~ /$re/i, @images;
       }
       else {
	 @iter_images = @unnamed_images;
       }
       $current_image = undef;
     },
     iterate_images => 
     sub { 
       if (++$image_index < @iter_images) {
	 $current_image = $iter_images[$image_index];
       }
       else {
	 $current_image = undef;
       }
       $current_image;
     },
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
	 $im = $current_image;
       }

       return $self->_format_image($im, $align, $rest);
     },
     imagen => 
     sub {
       my ($arg, $acts, $funcname, $templater) = @_;
       my ($name, $align, @rest) =
	 DevHelp::Tags->get_parms($arg, $acts, $templater);
       my $rest = "@rest";

       my ($im) = grep lc $name eq lc $_->{name}, @images
	 or return '';

       $self->_format_image($im, $align, $rest);
     },
     ifImage => sub { $_[0] >= 1 && $_[0] <= @images },
     ifImages => 
     sub {
       my ($arg) = @_;
       if ($arg eq 'all' or $arg eq '') {
	 return @images;
       }
       elsif ($arg eq 'named') {
	 return grep $_->{name} ne '', @images;
       }
       elsif ($arg =~ m!^named\s+/([^/]+)/$!) {
	 my $re = $1;
	 return grep $_->{name} =~ /$re/i, @images;
       }
       elsif ($arg eq 'unnamed') {
	 return @unnamed_images;
       }
       else {
	 return 0;
       }
     },
     image_index => sub { $image_index },
     thumbimage => [ tag_thumbimage => $self, \$current_image, \@images ],
     BSE::Util::Tags->make_iterator(\@files, 'file', 'files'),
     BSE::Util::Tags->make_iterator(\@stepkids, 'stepkid', 'stepkids'),
     $art_it->make_iterator(undef, 'allkid', 'allkids', \@allkids, \$allkids_index),
     $art_it->make_iterator(undef, 'stepparent', 'stepparents', \@stepparents),
     top => [ \&tag_article, $self->{top} || $article, $cfg ],
     ifDynamic => $dynamic,
     ifAccessControlled => [ \&tag_ifAccessControlled, $article ],
    );

  if ($abs_urls) {
    my $oldurl = $acts{url};
    my $urlbase = $cfg->entryErr('site', 'url');
    $acts{url} =
      sub {
        my $value = $oldurl->(@_);
	return $value if $value =~ /^<:/; # handle "can't do it"
        unless ($value =~ /^\w+:/) {
          # put in the base site url
          $value = $urlbase . $value;
        }
        return $value;
      };
  }
  if ($dynamic && $cfg->entry('basic', 'ajax', 0)) {
    # make sure the ajax tags are left until we do dynamic replacement
    delete @acts{qw/ajax ifAjax/};
  }

  return %acts;
}

sub tag_ifStepAncestor {
  my ($article, $arg, $acts, $name, $templater) = @_;

  unless ($arg =~ /^\d+$/) {
    $acts->{$arg} or die "ENOIMPL\n";
    $arg = $acts->{$arg} && $templater->perform($acts, $arg, 'id')
      or return;
  }
  return 0 if $article->{id} < 0;
  return $article->{id} == $arg || $article->is_step_ancestor($arg);
}

sub tag_ifDynamic {
  my ($self, $top) = @_;

  # this is to support pregenerated pages being handled as dynamic pages
  $self->{force_dynamic} and return 1;

  UNIVERSAL::isa($top, 'Article') ? $top->is_dynamic : 0;
}

sub tag_ifAccessControlled {
  my ($article, $arg, $acts, $funcname, $templater) = @_;

  if ($arg) {
    if ($acts->{$arg}) {
      my $id = $templater->perform($acts, $arg, 'id');
      $article = Articles->getByPkey($id);
      unless ($article) {
	print STDERR "** Unknown article $id from $arg in ifAccessControlled\n";
	return 0;
      }
    }
    else {
      print STDERR "** Unknown article $arg in ifAccessControlled\n";
      return 0;
    }
  }

  return UNIVERSAL::isa($article, 'Article') ? 
    $article->is_access_controlled : 0;
}

# note: this is called by BSE::Formatter::thumbimage(), update that if
# this is changed
sub do_thumbimage {
  my ($self, $geo_id, $image_id, $field, $images, $rcurrent) = @_;

  my $im;
  if ($image_id eq '-' && $rcurrent) {
    $im = $rcurrent
      or return "** No current image in images iterator **"
  }
  elsif ($image_id =~ /^\d+$/) {
    $image_id >= 1 || $image_id <= @$images
      or return "** Out of range image index **";

    $im = $images->[$image_id-1];
  }
  elsif ($image_id =~ /^[^\W\d]\w*$/) {
    ($im) = grep $_->{name} eq $image_id, @$images
      or return "** Unknown images identifier $image_id **";
  }

  return $self->_sthumbimage_low($geo_id, $im, $field);
}

sub generate {
  my ($self, $article, $articles) = @_;

  my $html = BSE::Template->get_source($article->{template}, $self->{cfg});
  $html =~ s/<:\s*embed\s+(?:start|end)\s*:>//g;

  return $self->generate_low($html, $article, $articles, 0);
}

sub tag_movekid {
  my ($self, $rindex, $rchildren, $article, $args, $acts, 
      $funcname, $templater) = @_;

  $self->{admin} or return '';
  @$rchildren or return '';

  my ($img_prefix, $urladd) = 
    DevHelp::Tags->get_parms($args, $acts, $templater);
  defined $img_prefix or $img_prefix = '';
  defined $urladd or $urladd = '';

  my $top = $self->{top} || $article;
  my $refreshto = $ENV{SCRIPT_NAME} . "?id=$top->{id}$urladd";
  my $down_url = "";
  if ($$rindex < $#$rchildren) {
    $down_url = "$CGI_URI/admin/move.pl?id=$rchildren->[$$rindex]{id}&d=down";
  }
  my $up_url = "";
  if ($$rindex > 0) {
    $up_url = "$CGI_URI/admin/move.pl?id=$rchildren->[$$rindex]{id}&d=up";
  }

  return make_arrows($self->{cfg}, $down_url, $up_url, $refreshto, $img_prefix);
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

Iterates over the unnamed images for the given article.

=item iterator ... images all

Iterates over all images for the article.

=item iterator ... images named

Iterates over the named images for the article.

=item iterator ... images named /regexp/

Iterates over images with names matching the given regular expression.
Note that if the expression matches an empty string then unnamed
images will be included.

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

=item ifImages all

Conditional tag, true if the article has any images.

=item ifImages named

Conditional tag, true if the article has any named images.

=item ifImages named /regexp/

Conditional tag, true if the article has any named images, where the
name matches the regular expression.

=item ifImages unnamed

Conditional tag, true if the article has any unnamed images.

=item embed child

This has been made more general and been moved, see L<Generate/embed child>.

=item ifDynamic

Tests if the article is dynamically generated.

=item top I<field>

Toplevel article being generated.  This is the page that any articles
are being embedded in.

=item iterator ... files

Iterates over the files attached to the article, setting the file tag.

=item file I<field>

Information from the current file in the files iterator.

The file fields are:

=over

=item *

id - identifier for this file

=item *

articleId - article this file belongs to

=item *

displayName - the filename of the file as displayed

=item *

filename - filename of the file as stored on disk,

=item *

sizeInBytes - size of the file in bytes.

=item *

description - the entered description of the file

=item *

contentType - the MIME content type of the file

=item *

displayOrder - number used to control the listing order.

=item *

forSale - non-zero if the file needs to be paid for to be downloaded.

=item *

download - if this is non-zero BSE will attempt to make the browser
download the file rather than display it.

=item *

whenUploaded - date/time when the file was uploaded.

=item *

requireUser - if non-zero the user must be logged on to download this
file.

=item *

notes - longer descriptive text.

=item *

name - identifier for the file for filelink[]

=item *

hide_from_list - if non-zero the file won't be listed by the files
iterator, but will still be available to filelink[].

=back

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

=item lastModifiedBy

Set the the current admin user logon if access_control is enabled in the cfg.

=item created

Set to the current date time when a new article is created.

=item createdBy

Set to the current admin user logon if access_control is enabled in
the cfg.

=item author

A user definable field for attributing the article author.

=item pageTitle

An alternate article title which can be used to make search engine
baited oage titles.

=item metaDescription

Article metadata description, used as metadata in the generated HTML
output.

=item metaKeywords

Article metadata keywords, used as metadata in the generated HTML
output.

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

=item flags

Flags which can be checked by code or template tags to control behaviours 
specific the the article.

=item force_dynamic

Forces a page to be displayed dynamically with page.pl regardless of
access control.

=item inherit_siteuser_rights

Controls whether the article inherits its parents access controls.

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

=item admin

Produces buttons and links used for administering the article.

This tag can use a specialized template if it's available.  If you
call it with a parameter, <:admin I<template>:> then it will use
template C<< admin/adminmenu/I<template>.tmpl >>.  When used in an
article template C<< <:admin:> >> behaves like C<< <:admin article:>
>>, when used in a catalog template C<< <:admin:> >> behaves like C<<
<:admin catalog:> >>, when used in a product template C<< <:admin:> >>
behaves like C<< <:admin product:> >>.  See L<Admin Menu Templates>
for the tags available in admin menu templates.

If the template doesn't exist then the old behaviour applies.

=back

=head2 Admin Menu Templates

These tags can be used in the templates included by the C<< <:admin:>
>> tag.

The basic template tags and ifUserCan tag can be used in admin menu
templates.

=over

=item article field

Retrieves a field from the current article.

=item parent field

Retrieves a field from the parent of the current article.

=item ifParent

Conditional tag, true if the current article has a parent.

=item ifEmbedded

Conditional tag, true if the current article is embedded in another
article, in this context.

=back

=cut
