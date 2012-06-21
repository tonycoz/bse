package BSE::Util::DynamicTags;
use strict;
use BSE::Util::Tags qw(tag_article);
use BSE::Util::HTML;
use base 'BSE::ThumbLow';
use base 'BSE::TagFormats';
use BSE::CfgInfo qw(custom_class);

our $VERSION = "1.025";

=head1 NAME

BSE::Util::DynamicTags - common dynamic page tags for BSE.

=head1 SYNOPSIS

  # in the code
  my %acts =
    (
     $req->dyn_user_tags(),
     ...
    );

  # in the page

  <:user userId:>
  ...

=head1 DESCRIPTION

This module defines the common set of tags available on public dynamic
pages.

=head1 METHODS

=over

=item new

Create a new tags object, accepts a single parameter which is a
L<BSE::Request> object.

=cut

sub new {
  my ($class, $req) = @_;
  return bless { req => $req }, $class;
}

=item tags

Returns the common tags.

=cut

sub tags {
  my ($self) = @_;
  
  my $req = $self->{req};
  return
    (
     BSE::Util::Tags->common($req),
     user => [ \&tag_user, $req ],
     ifUser => [ \&tag_ifUser, $req ],
     ifUserCanSee => [ \&tag_ifUserCanSee, $req ],
     $self->dyn_article_iterator('dynlevel1s', 'dynlevel1'),
     $self->dyn_article_iterator('dynlevel2s', 'dynlevel2'),
     $self->dyn_article_iterator('dynlevel3s', 'dynlevel3'),
     $self->dyn_article_iterator('dynallkids_of', 'dynofallkid'),
     $self->dyn_article_iterator('dynallkids_of2', 'dynofallkid2'),
     $self->dyn_article_iterator('dynallkids_of3', 'dynofallkid3'),
     $self->dyn_article_iterator('dynchildren_of', 'dynofchild'),
     $self->dyn_iterator('dyncart', 'dyncartitem'),
     $self->dyn_article_iterator('wishlist', 'wishlistentry'),
     $self->dyn_iterator('dynunused_tagcats', 'dynunused_tagcat'),
     $self->dyn_iterator('dynunused_tags', 'dynunused_tag'),
     $self->dyn_iterator('dyntags', 'dyntag'),
     url => [ tag_url => $self ],
     dyncarttotalcost => [ tag_dyncarttotal => $self, 'total_cost' ],
     dyncarttotalunits => [ tag_dyncarttotal => $self, 'total_units' ],
     ifAncestor => 0,
     ifUserMemberOf => [ tag_ifUserMemberOf => $self ],
     dthumbimage => [ tag_dthumbimage => $self ],
     dgthumbimage => [ tag_dgthumbimage => $self ],
     dyntarget => [ tag_dyntarget => $self ],
     $self->dyn_iterator('dynvimages', 'dynvimage'),
     dynvimage => [ tag_dynvimage => $self ],
     dynvthumbimage => [ tag_dynvthumbimage => $self ],
     recaptcha => [ tag_recaptcha => $self, $req ],
     dyncatmsg => [ tag_dyncatmsg => $self, $req ],
     $self->dyn_iterator("userfiles", "userfile"),
     $self->dyn_iterator_obj("paidfiles", "paidfile"),
     price => [ tag_price => $self ],
     ifTieredPricing => [ tag_ifTieredPricing => $self ],
     $self->_custom_tags,
    );
}

sub _custom_tags {
  my ($self) = @_;

  $self->cfg->entry('custom', 'dynamic_tags')
    or return;

  return custom_class($self->cfg)->dynamic_tags($self->req);
}

=item cfg

Return a cfg object.

=cut

sub cfg {
  return $_[0]{req}->cfg;
}

=item cgi

Return the cgi object.

=cut

sub cgi {
  return $_[0]{req}->cgi;
}

=item req

Return the request object.

=cut

sub req {
  return $_[0]{req};
}

=item admin_mode

Return true if in admin mode.

=cut

sub admin_mode {
  return 0;
}

=back

=head1 COMMON DYNAMIC TAGS

=over

=item ifUser
=synopsis <:if User:><:user userId:><:or:>Not logged in<:eif:>

With parameters, check if there is a user currenly logged in.

Without, check if the given attribute of the currently logged in user
is a true perl value.

=cut

sub tag_ifUser {
  my ($req, $args) = @_;

  my $user = $req->siteuser
    or return '';
  if ($args) {
    return $user->{$args};
  }
  else {
    return 1;
  }
}

=item user

Retrieve an attribute from the currently logged in user.

Returns an empty string if the user isn't logged in or if the
attribute is unknown.

=cut

sub tag_user {
  my ($req, $args) = @_;

  my $siteuser = $req->siteuser
    or return '';

  exists $siteuser->{$args}
    or return '';

  escape_html($siteuser->{$args});
}

=item ifUserCanSee
=synopsis <:ifUserCanSee 3:><a href="/shop/">See the shop</a><:or:><:eif:>

Tests if the currently logged in siteuser has access to the named or
numbered article.

=cut

sub tag_ifUserCanSee {
  my ($req, $args) = @_;

  $args 
    or return 0;

  my $article;
  if ($args =~ /^\d+$/) {
    require Articles;
    $article = Articles->getByPkey($args);
  }
  else {
    $article = $req->get_article($args);
  }
  $article
    or return 0;

  $req->cfg->entry('basic', 'admin_sees_all', 1)
    and return 1;

  $req->siteuser_has_access($article);
}

=item ifUserMemberOf

Test if the currently logged in user is a member of the named group.

Accepts [] style parameters.

=cut

sub tag_ifUserMemberOf {
  my ($self, $args, $acts, $func, $templater) = @_;

  my $req = $self->{req};

  my $user = $req->siteuser
    or return 0; # no user, no group

  my ($name) = DevHelp::Tags->get_parms($args, $acts, $templater);

  $name
    or return 0; # no group name
  
  require BSE::TB::SiteUserGroups;
  my $group = BSE::TB::SiteUserGroups->getByName($req->cfg, $name);
  unless ($group) {
    print STDERR "Unknown group name '$name' in ifUserMemberOf\n";
    return 0;
  }

  return $group->contains_user($user);
}

=item dyntarget
=synopsis <:dyntarget user a_logon 1:>

Generate a url to the specified script with the given parameters.

Accepts [] style parameters.

=cut

sub tag_dyntarget {
  my ($self, $args, $acts, $func, $templater) = @_;

  my $req = $self->{req};

  my ($script, $target, @options) = DevHelp::Tags->get_parms($args, $acts, $templater);

  for my $option (@options) {
    $option = unescape_html($option);
  }

  return escape_html($req->user_url($script, $target, @options));
}

=item url
=synopsis <:url dynofallkid:>

Generate a link to the specified article, taking admin mode into
account.

=cut

sub tag_url {
  my ($self, $name, $acts, $func, $templater) = @_;

  my $item = $self->{admin} ? 'admin' : 'link';
  my $article = $self->{req}->get_article($name)
    or return "** unknown article $name **";

  my $value;
  if ($item eq 'link' and ref $article ne 'HASH') {
    $value = $article->link($self->{req}->cfg);
  }
  else {
    $value = $article->{$item};
  }

  # we don't know our context, so always produce absolute URLs
  if ($value !~ /^\w+:/) {
    $value = $self->{req}->cfg->entryErr('site', 'url') . $value;
  }

  return escape_html($value);
}

=item iterator dynlevel1s

Iterate over level 1 articles.

=cut

sub iter_dynlevel1s {
  my ($self, $unused, $args) = @_;

  my $result = $self->get_cached('dynlevel1');
  $result
    and return $result;

  require Articles;
  $result = $self->access_filter(Articles->listedChildren(-1));
  $self->set_cached(dynlevel1 => $result);

  return $result;
}

=item iterator dynlevel2s

Iterate over the children of the dynlevel1 article.

=cut

sub iter_dynlevel2s {
  my ($self, $unused, $args) = @_;

  my $req = $self->{req};
  my $parent = $req->get_article('dynlevel1')
    or return [];

  my $cached = $self->get_cached('dynlevel2');
  $cached && $cached->[0] == $parent->{id}
    and return $cached->[1];

  require Articles;
  my $result = $self->access_filter(Articles->listedChildren($parent->{id}));
  $self->set_cached(dynlevel2 => [ $parent->{id}, $result ]);

  return $result;
}

=item iterator dynlevel3s

Iterate over the children of the dynlevel2 article.

=cut

sub iter_dynlevel3s {
  my ($self, $unused, $args) = @_;

  my $req = $self->{req};
  my $parent = $req->get_article('dynlevel2')
    or return [];

  my $cached = $self->get_cached('dynlevel3');
  $cached && $cached->[0] == $parent->{id}
    and return $cached->[1];

  require Articles;
  my $result = $self->access_filter( Articles->listedChildren($parent->{id}));
  $self->set_cached(dynlevel3 => [ $parent->{id}, $result ]);

  return $result;
}

=item dynallkids_of

Also dynallkids_of2, dynallkids_of3

Iterate over all children of the each of the specified article names
or ids.

=cut

sub iter_dynallkids_of {
  my ($self, $unused, $args, $acts, $templater, $state) = @_;

  $state->{parentid} = undef;
  my @ids = map { split } DevHelp::Tags->get_parms($args, $acts, $templater);
  for my $id (@ids) {
    unless ($id =~ /^\d+$|^-1$/) {
      $id = $self->{req}->get_article($id);
    }
  }
  @ids = grep defined && /^\d+$|^-1$/,
    map ref() ? $_->{id} : $_, @ids;

  @ids == 1 and $state->{parentid} = $ids[0];

  require Articles;
  return $self->access_filter(map Articles->all_visible_kids($_), @ids);
}

sub tags_for_dynallkids_of {
  my ($self, $unused, $args, $acts, $templater) = @_;

  my @ids = map { split } DevHelp::Tags->get_parms($args, $acts, $templater);
  for my $id (@ids) {
    unless ($id =~ /^\d+$|^-1$/) {
      $id = $self->{req}->get_article($id);
    }
  }
  @ids = grep defined && /^\d+$|^-1$/,
    map ref() ? $_->{id} : $_, @ids;

  @ids
    or return { tags => [], members => [] };

  require Articles;
  if (@ids == 1) {
    return Articles->all_visible_kid_tags($ids[0]);
  }
  else {
    my %tags;
    my @members;
    for my $id (@ids) {
      my $more_tags = Articles->all_visible_kid_tags($id);
      for my $tag (@{$more_tags->{tags}}) {
	$tags{$tag->id} = $tag;
      }
      push @members, @{$more_tags->{members}};
    }

    return
      {
       tags => [ values %tags ],
       members => \@members,
      };
  }
}

*iter_dynallkids_of2 = \&iter_dynallkids_of;
*iter_dynallkids_of3 = \&iter_dynallkids_of;

*tags_for_dynallkids_of2 = \&tags_dynallkids_of;
*tags_for_dynallkids_of3 = \&tags_dynallkids_of;

=item dynchildren_of

Iterate over direct children of each of the specified article names or
ids.

=cut

sub iter_dynchildren_of {
  my ($self, $unused, $args, $acts, $templater) = @_;

  my @ids = map { split } DevHelp::Tags->get_parms($args, $acts, $templater);
  for my $id (@ids) {
    unless ($id =~ /^\d+$|^-1$/) {
      $id = $self->{req}->get_article($id);
    }
  }
  @ids = grep defined && /^\d+$|^-1$/, @ids;

  require Articles;
  return $self->access_filter( map Articles->listedChildren($_), @ids);
}

=item iterator dyncart

Iterate over the contents of the cart.

=cut

sub iter_dyncart {
  my ($self, $unused, $args) = @_;

  my $cart = $self->_cart
    or return [];

  return $cart->{cart};
}

=item dyncarttotal

The total cost of the items in the cart, in cents.

=cut

sub tag_dyncarttotal {
  my ($self, $field, $args) = @_;

  my $cart = $self->_cart
    or return 0;

  return $cart->{$field};
}

=item iterator dynvimages

A dynamic version of the vimages iterator.

Items are vimage (which acts like other image tags) and dynvthumbimage.

=cut

sub iter_dynvimages {
  my ($self, $context, $args, $acts, $templater) = @_;

  my $re;
  my $num;
  if ($args =~ s!\s+named\s+/([^/]+)/$!!) {
    $re = $1;
  }
  elsif ($args =~ s!\s+numbered\s+(\d+)$!!) {
    $num = $1;
  }
  my @ids = map { split /[, ]/ } 
    DevHelp::Tags->get_parms($args, $acts, $templater);
  my @images;
  for my $article_id (@ids) {
    my @articles = $self->_find_articles($article_id);
    for my $article (@articles) {
      my @aimages = $article->images;
      if (defined $re) {
	push @images, grep $_->{name} =~ /$re/, @aimages;
      }
      elsif (defined $num) {
	if ($num >= 0 && $num <= @aimages) {
	  push @images, $aimages[$num-1];
	}
      }
      else {
	push @images, @aimages;
      }
    }
  }

  return \@images;
}

=item dynvimage field

=item dynvimage 

Item for iterator dynvimages

=cut

sub tag_dynvimage {
  my ($self, $args) = @_;

  my $im = $self->{req}->get_article('dynvimage')
    or return '** not in dynvimages iterator **';

  my ($align, $rest) = split ' ', $args, 2;

  return $self->_format_image($im, $align, $rest);
}

=item dynvthumbimage geometry field

=item dynvthumbimage geometry

Thumbnail of the current vimage.

=cut

sub tag_dynvthumbimage {
  my ($self, $args) = @_;

  my $im = $self->{req}->get_article('dynvimage')
    or return '** not in dynvimages iterator **';

  my ($geo, $field) = split ' ', $args;

  return $self->_thumbimage_low($geo, $im, $field, $self->{req}->cfg);
}

sub _find_articles {
  my ($self, $article_id) = @_;

  if ($article_id =~ /^\d+$/) {
    my $result = Articles->getByPkey($article_id);
    $result or print STDERR "** Unknown article id $article_id **\n";
    return $result ? $result : ();
  }
  elsif ($article_id =~ /^alias\((\w+)\)$/) {
    my $result = Articles->getBy(linkAlias => $1);
    $result or print STDERR "** Unknown article alias $article_id **\n";
    return $result ? $result : ();
  }
  elsif ($article_id =~ /^childrenof\((.*)\)$/) {
    my $id = $1;
    if ($id eq '-1') {
      return Articles->all_visible_kids(-1);
    }
    else {
      my @parents = $self->_find_articles($id)
	or return;
      return map $_->all_visible_kids, @parents
    }
  }
  else {
    my $article = $self->{req}->get_article($article_id);
    $article
      and return $article;
  }

  print STDERR "** Unknown article identifier $article_id **\n";

  return;
}

=item iterator wishlist

Iterate over the items in the logged in user's wishlist.

=cut

sub iter_wishlist {
  my ($self) = @_;

  my $user = $self->req->siteuser
    or return [];
  return [ $user->wishlist ];
}

=item iterator dynunused_tagcats

Iterate over the the tag categories of unused tags in the articles
selected by the given tags: and filter: parameters.

Usage:

=over

C<<iterator begin dynunused_tagcats I<iterator-name> I<onlyone-opt> I<iterator arguments> tags:I<tags-filter> >>

=back

You must supply a tags: filter, even if it's just "".

There will be an iteration with an empty I<name> for each tag without
a category.

If a parameter "onlyone" is supplied then the list of tag categories
will not include tag categories that appear in the tags filter.

If a filter C<<category: I<expression> >> is supplied, then only
category names matching I<expression> will be included.

Each entry has:

=over

=item * name - name of the category

=item * nocat - a category-less tag

=item * ind - a unique key for this category.

=back

=cut

sub iter_dynunused_tagcats {
  my ($self, $unused, $args, $acts, $templater, $state) = @_;

  unless ($args =~ s/^(\w+)\s*//) {
    print STDERR "* dynunused_tagcats: missing iterator name *\n";
    return [];
  }

  my $iter = $1;

  my $method = "iter_$iter";
  unless ($self->can($method)) {
    print STDERR "* Unknown iterator $iter *\n";
    return [];
  }
  
  my $tags_method = "tags_for_$iter";

  my $filter = $self->{filter};
  my $selected_tags = $filter->{tags};
  unless ($selected_tags) {
    print STDERR "* dynunused_tagcats($iter): no tags: supplied *\n";
    return [];
  }

  my $only_one = $args =~ s/^\s*onlyone\s+//;
  my $tags;
  my %selected_cats = map { $_ => 1 }
    map { lc ((BSE::TB::Tags->split_name($_))[0]) }
      @{$selected_tags || []};

  my $only_cat;
  if ($args =~ s/\bcategory:\s*(.*)$//) {
    ($only_cat) = $templater->get_parms($1, $acts);
  }

  my $context = $self->{context}{$iter};
  my %state =
    (
     plural => $iter,
     single => "unknown",
     context => $context,
    );

  if ($self->can($tags_method)
      && !$self->cfg->entry('basic', 'dynamic_access_filter', 1)
      && !$filter->{filter}) {
    my $info = $self->$tags_method($context, $args, $acts, $templater);
    my @tag_ids;
    my $all_found = 1;
    my %named = map { lc $_->name => $_ } @{$info->{tags}};
    my %name_by_id = map { $_->id => $_->name } @{$info->{tags}};

    # find which article ids have the tags we need
  TAGS:
    for my $tag_name (@$selected_tags) {
      my $tag = $named{lc $tag_name};
      unless ($tag) {
	# no articles can match an unknown tag, so there's no unused tags
	return [];
      }
      push @tag_ids, $tag->{id};
    }
    my %lookup;
    for my $member (@{$info->{members}}) {
      $lookup{$member->{owner_id}}{$member->{tag_id}} = $name_by_id{$member->{tag_id}};
    }

    my %extras;
  ARTICLE:
    for my $article_id (keys %lookup) {
      my $tags = $lookup{$article_id} || {};
      for my $tag_id (@tag_ids) {
	delete $tags->{$tag_id}
	  or next ARTICLE;
      }
      ++$extras{$_} for values %$tags;
    }
    $tags = \%extras;

    delete $filter->{tags};
  }
  else {
    my $ignored = $self->_do_filter
      (\%state, $filter, $args, $acts, $templater, $self->$method
       ($context, $args, $acts, $templater, \%state));
    keys %$filter
      or $self->{filter} = undef;

    $tags = $self->{tags}{$iter};
  }

  require Articles;

  return Articles->categorize_tags
    (
     [ keys %$tags ],
     $selected_tags,
     {
      onlycat => $only_cat,
      onlyone => $only_one,
      counts => $tags,
     },
    );
}

=item iterator dynunsed_tags

Iterate over the unused tags in a category from dynunused_tagcats.

Each entry has:

=over

=item * name - the full name of the tag, including category

=item * cat - the category only

=item * val - the value only

=back

=cut

sub iter_dynunused_tags {
  my ($self, $unused, $args) = @_;

  my $cat = $self->{current}{dynunused_tagcats}
    or return;

  return $cat->{vals};
}

=item dyntags
=synopsis <:iterator begin dyntags [lcgi tags]:>

Iterate over a list of tags.

=cut

sub iter_dyntags {
  my ($self, $unused, $args, $acts, $templater) = @_;

  my @tags = grep /\S/, map { split '/' } $templater->get_parms($args, $acts);

  my @out;
  for my $tag (@tags) {
    my ($cat, $val) = BSE::TB::Tags->split_name($tag);

    push @out,
      {
       name => BSE::TB::Tags->make_name($cat, $val),
       cat => $cat,
       val => $val
      };
  }

  return \@out;
}

sub access_filter {
  my ($self, @articles) = @_;

  my $req = $self->{req};

  my $admin_sees_all = $req->cfg->entry('basic', 'admin_sees_all', 1);

  $admin_sees_all && $self->{admin} and 
    return \@articles;

  $req->cfg->entry('basic', 'dynamic_access_filter', 1)
    or return \@articles;

  return [ grep $req->siteuser_has_access($_), @articles ];
}

=item dthumbimage

Either:

=over

C<< dynthumbimage I<article> I<geometry> I<image> I<field> >>

or

C<< dthumbimage I<article> I<geometry> I<image> >>

=back

Similar to thumbimage/gthumbimage, this allows you to retrieve images
from a given article, which article can either be a number or a named
article in the current context.

geometry and field are as for the static thumbimage tag.

image is a comma separated list of match operators, eg:

  <:dthumbimage result search search,/^display_$/,1 :>

on a search page will display either the image with an id of search,
the first image found with an identifier starting with "display_" or
the first image of the article.

Possible match operators are:

=over

=item *

/regexp/ - a regular expression matched against the image identifier

=item *

index - a numeric image index, where 1 is the first image

=item *

identifier - a literal image identifier

=back

=cut

sub tag_dthumbimage {
  my ($self, $args) = @_;

  my ($article_id, $geometry, $image_tags, $field) = split ' ', $args;
  
  my $article;
  if ($article_id =~ /^\d+$/) {
    require Articles;
    $article = Articles->getByPkey($args);
  }
  else {
    $article = $self->{req}->get_article($article_id);
  }
  $article
    or return '';

  my @images = $article->images;
  my $im;
  for my $tag (split /,/, $image_tags) {
    if ($tag =~ m!^/(.*)/$!) {
      my $re = $1;
      ($im) = grep $_->{name} =~ /$re/i, @images
	and last;
    }
    elsif ($tag =~ /^\d+$/) {
      if ($tag >= 1 && $tag <= @images) {
	$im = $images[$tag-1];
	last;
      }
    }
    elsif ($tag =~ /^[^\W\d]\w*$/) {
      ($im) = grep $_->{name} eq $tag, @images
	and last;
    }
  }
  $im
    or return '';
  
  return $self->_thumbimage_low($geometry, $im, $field, $self->{req}->cfg);
}

=item dgthumbimage

=over

C<<dgthumbimage I<geometry> I<name> I<field> >>

C<<dgthumbimage I<geometry> I<name> >>

=back

Format a thumbnail for a global image, in dynamic context.

=cut

sub tag_dgthumbimage {
  my ($self, $args, $acts, $func, $templater) = @_;

  my ($geometry, $name, $field) = 
    DevHelp::Tags->get_parms($args, $acts, $templater);

  require BSE::TB::Images;
  my ($im) = BSE::TB::Images->getBy(articleId => -1,
				    name => $name)
    or return "* no such global image $name *";
  
  return $self->_thumbimage_low($geometry, $im, $field, $self->{req}->cfg);
}

=item recaptcha

Category: dynamic

Produce a recaptcha block.

No parameters, though this may change.

=cut

sub tag_recaptcha {
  my ($self, $req, $args) = @_;

  defined $args or $args = '';
  require Captcha::reCAPTCHA;
  my $section = $args =~ /\S/ ? "recaptcha $args" : "recaptcha";
  my $api_key = $req->cfg->entry('recaptcha', 'api_public_key')
    or return "** No reCAPTCHA api_public_key defined **";

  my %opts = $req->cfg->entries($section);
  delete @opts{qw/api_public_key api_private_key/};

  my $c = Captcha::reCAPTCHA->new;

  return $c->get_html($api_key, $req->recaptcha_result, scalar $req->is_ssl, \%opts);
}

=item dyncatmsg msgid parameters...

Return a message from the message catalog.

=cut

sub tag_dyncatmsg {
  my ($self, $req, $args, $acts, $func, $templater) = @_;

  my ($id, @params) = DevHelp::Tags->get_parms($args, $acts, $templater);
  $id or return '* no message id for dyncatmsg *';
  $id =~ s/^msg:// or return '* invalid message id, no msg: prefix *';
  my $cat = $req->message_catalog;

  my $html = $cat->html($req->language, $id, \@params);

  if ($self->{admin}) {
    $html = qq(<div class="bse_catmsg">$html</div>);
  }

  return $html;
}

my %num_file_fields = map { $_=> 1 }
  qw/id owner_id size_in_bytes/;

sub iter_userfiles {
  my ($self, $unused, $args) = @_;

  my $req = $self->{req};
  my $user = $req->siteuser
    or return [];

  my @files = map $_->data_only, $user->visible_files($req->cfg);
  require BSE::TB::OwnedFiles;
  my %catnames = map { $_->{id} => $_->{name} } BSE::TB::OwnedFiles->categories($req->cfg);

  # produce a url for each file
  my $base = '/cgi-bin/user.pl?a_downufile=1&id=';
  for my $file (@files) {
    $file->{url} = $base . $file->{id};
    $file->{catname} = $catnames{$file->{category}} || $file->{category};
    $file->{new} = $file->{modwhen} gt $user->previousLogon;
  }
  defined $args or $args = '';

  my $sort;
  if ($args =~ s/\bsort:\s?(-?\w+(?:,-?\w+)*)\b//) {
    $sort = $1;
  }
  my $cgi_sort = $req->cgi->param('userfile_sort');
  $cgi_sort
    and $sort = $cgi_sort;
  if ($sort && @files > 1) {
    my @fields = map 
      {
	my $work = $_;
	my $rev = $work =~ s/^-//;
	[ $rev, $work ]
      } split /,/, $sort;

    @fields = grep exists $files[0]{$_->[1]}, @fields;

    @files = sort
      {
	for my $field (@fields) {
	  my $name = $field->[1];
	  my $diff = $num_file_fields{$name}
	    ? $a->{$name} <=> lc $b->{$name}
	      : $a->{$name} cmp lc $b->{$name};
	  if ($diff) {
	    return $field->[0] ? -$diff : $diff;
	  }
	}
	return 0;
      } @files;
  }

  $args =~ /\S/
    or return \@files;

  if ($args =~ /^\s*filter:(.*)$/) {
    my $expr = $1;
    my $func = eval 'sub { my ($file, $state) = @_;' .  $expr . '}';
    unless ($func) {
      print STDERR "** Cannot compile userfile filter $expr: $@\n";
      return;
    }
    my %state;
    return [ grep $func->($_, \%state), @files ];
  }

  if ($args =~ /^\s*(!)?(\w+(?:,\w+)*)\s*$/) {
    my ($not, $cats) = ( $1, $2 );
    my %matches = map { $_ => 1 } split ',', $cats, -1;
    if ($not) {
      return [ grep !$matches{$_->{category}}, @files ];
    }
    else {
      return [ grep $matches{$_->{category}}, @files ];
    }
  }

  print STDERR "** unparsable arguments to userfile: $args\n";

  return [];
}

=item iterator paid_files

Iterates over the files the user has paid for.

=cut

sub iter_paidfiles {
  my ($self, $unused, $args) = @_;

  my $user = $self->req->siteuser
    or return [];

  return [ $user->paid_files ];
}

sub tag_dynmove {
  my ($self, $rindex, $rrdata, $url_prefix, $args, $acts, $templater) = @_;

  return '' unless $self->admin_mode;

  return '' unless $$rrdata && @$$rrdata > 1;

  require BSE::Arrows;
  *make_arrows = \&BSE::Arrows::make_arrows;

  my ($img_prefix, $url_add) = 
    DevHelp::Tags->get_parms($args, $acts, $templater);
  defined $img_prefix or $img_prefix = '';
  defined $url_add or $url_add = '';
  my $refresh_to = $ENV{SCRIPT_NAME} . "?id=" . 
    $self->{req}->get_article('dynarticle')->{id} . $url_add;
  my $move = "$Constants::CGI_URI/admin/move.pl?";
  $move .= $url_prefix . '&' if $url_prefix;
  $move .= 'd=swap&id=' . $$$rrdata[$$rindex]{id} . '&';
  my $down_url = '';
  if ($$rindex < $#$$rrdata) {
    $down_url = $move . 'other=' . $$$rrdata[$$rindex+1]{id};
  }
  my $up_url = '';
  if ($$rindex > 0) {
    $up_url = $move . 'other=' . $$$rrdata[$$rindex-1]{id};
  }

  return make_arrows($self->{req}->cfg, $down_url, $up_url, $refresh_to, $img_prefix);
}

=item price

Return the price of a product.

One of two parameters:

=over

=item *

I<product> - the product to fetch the price for.  This can be a name
or [] evaluating to a product id.

=item *

I<field> - "price" to fetch the price, "discount" to fetch the
difference from the base price, "discountpc" to fetch the discount in
percent (whole number).  Returns the price if no I<field> is
specified.

=back

=cut

sub tag_price {
  my ($self, $args, $acts, $func, $templater) = @_;

  my ($id, $field) = $templater->get_parms($args, $acts);
  $field ||= "price";

  my $work;
  if ($id =~ /^[0-9]+$/) {
    require Products;
    $work = Products->getByPkey($id)
      or return "** unknown product $id **";
  }
  else {
    $work = $self->{req}->get_article($id)
      or return "** unknown product name $id **";
  }

  my ($price, $tier) = $work->price(user => scalar $self->{req}->siteuser);

  if ($field eq "price") {
    return $price;
  }
  elsif ($field eq "discount") {
    return $work->retailPrice - $price;
  }
  elsif ($field eq "discountpc") {
    $work->retailPrice or return "";
    return sprintf("%.0f", ($work->retailPrice - $price) / $work->retailPrice * 100);
  }
  else {
    return "** unknown field $field **";
  }
}

=item ifTieredPricing

Conditional to check if there's tiered pricing.

=cut

sub tag_ifTieredPricing {
  require Products;
  my @tiers = Products->pricing_tiers;

  return scalar @tiers;
}

=back

=head2 Dynamic iterator filter syntax

There a two types filters:

=over

=item * code filters - filters specified as perl code

=item * tag filters - filtering on tags (articles only)

=back

=head3 Code filters

Specified as:

=over

C<< filter: I<perl code> >>

=back

The text C<ARTICLE> is replaced with the article being tested.

The text C<<[I<column-name>]>> is replaced with that attribute of the
article.

=head3 Tag filters

Should be a simple [] expression specifying the tags to filter on:

=over

C<tags: [lcgi tags]>

=back

=cut

my $cols_re; # cache for below

sub _get_filter {
  my ($self, $state, $rargs, $acts, $templater) = @_;

  my %filter;

  if ($$rargs =~ s/tags:\s*(.*)\z//s) {
    my $expr = $1;
    my @match = $templater->get_parms($expr, $acts);

    # always add the tags filter even if no tags were listed
    # this means the other tag stuff continues to work
    my @tags = grep length, map split('/'), @match;

    $filter{tags} = \@tags;
  }

  if ($$rargs =~ s/filter:\s+(.*)\z//s) {
    my $expr = $1;
    my $orig_expr = $expr;
    unless ($cols_re) {
      require Articles;
      my $cols_expr = '(' . join('|', Article->columns) . ')';
      $cols_re = qr/\[$cols_expr\]/;
    }
    $expr =~ s/$cols_re/\$article->{$1}/g;
    $expr =~ s/ARTICLE/\$article/g;
    #print STDERR "Expr $expr\n";
    my $filter;
    $filter = eval 'sub { my $article = shift; '.$expr.'; }';
    if ($@) {
      print STDERR "** Failed to compile filter expression >>$expr<< built from >>$orig_expr<<\n";
      return;
    }

    $filter{code} = $filter;
  }

  return \%filter;
}

sub _do_filter {
  my ($self, $state, $filter, $args, $acts, $templater, $articles) = @_;

  $filter
    or return $articles;

  if (my $code = delete $filter->{code}) {
    $articles = [ grep $code->($_), @$articles ];
  }

  if (my $tags = delete $filter->{tags}) {
    my @out;
    my %extras;

    my $tags_method = "tags_for_$state->{plural}";

    if ($self->can($tags_method)) {
      # should have:
      # tags - tags used for these articles
      # members - member objects for these articles
      my $info = $self->$tags_method($state->{context}, $args, $acts, $templater);

      my @tag_ids;
      my $all_found = 1;
      my %named = map { lc $_->name => $_ } @{$info->{tags}};
      my %name_by_id = map { $_->id => $_->name } @{$info->{tags}};
    TAGS:
      for my $tag_name (@$tags) {
	my $tag = $named{lc $tag_name};
	unless ($tag) {
	  $all_found = 0;
	  last TAGS;
	}
	#push @tags, $tag;
	push @tag_ids, $tag->{id};
      }

      if ($all_found) {
	# build a lookup table
	my %lookup;
	for my $member (@{$info->{members}}) {
	  $lookup{$member->{owner_id}}{$member->{tag_id}} = $name_by_id{$member->{tag_id}};
	}

      ARTICLE:
	for my $art (@$articles) {
	  my $tags = $lookup{$art->id} || {};
	  for my $tag_id (@tag_ids) {
	    delete $tags->{$tag_id}
	      or next ARTICLE;
	  }
	  push @out, $art;
	  ++$extras{$_} for values %$tags;
	}
      }
    }
    else {
      my @tag_ids;
      my @tags;
      my $all_found = 1;
    TAGS:
      for my $tag_name (@$tags) {
	my $tag = Articles->getTagByName($tag_name);
	unless ($tag) {
	  # can't find a tag that doesn't exist
	  $all_found = 0;
	  last TAGS;
	}
	push @tags, $tag;
	push @tag_ids, $tag->id;
      }
      if ($all_found) {
      ARTICLE:
	for my $art (@$articles) {
	  my %tags = map { $_->id => $_ } $art->tag_objects;
	  for my $tag_id (@tag_ids) {
	    $tags{$tag_id}
	      or next ARTICLE;
	    delete $tags{$tag_id};
	  }
	  push @out, $art;
	  ++$extras{$_} for map $_->name, values %tags; # as long as they exist
	}
      }
    }

    $articles = \@out;

    $self->{tags}{$state->{plural}} = \%extras;
  }

  return $articles;
}

my $paged_re =
  qr(
      \bpaged:
	(?:(\w+)=)?  # optional per page variable
	([0-9]+)?    # optional per page default
	(?:,(\w+))?  # optional page selector
   )x;

sub _get_paged {
  my ($self, $state, $rargs) = @_;

  my $paged;
  if ($$rargs =~ s/$paged_re//) {
    $paged =
      {
       pp => $1 || "pp",
       perpage => $2 || 20,
       p => $3 || "p",
      };
  }

  return $paged;
}

sub _do_paged {
  my ($self, $state, $paged, $articles) = @_;

  $state->{totalcount} = @$articles;

  unless ($paged) {
    $state->{page} = 1;
    $state->{pagecount} = 1;
    $state->{poffset} = 0;
    $state->{perpage} = @$articles;
    $state->{nextpage} = '';
    $state->{prevpage} = '';
    $state->{firstnumber} = 1;
    $state->{lastnumber} = @$articles;
    return $articles;
  }

  my ($page) = $self->cgi->param($paged->{p});
  defined $page or $page = 1;
  $page =~ /^[0-9]+$/ or $page = 1;
  $page >= 1 or $page = 1;

  my ($pp) = $self->cgi->param($paged->{pp});
  defined $pp or $pp = $paged->{perpage};
  $pp =~ /^[0-9]+$/ or $pp = 20;
  $pp = int($pp);
  $pp >= 1 or $pp = 20;
  $state->{perpage} = $pp;

  $state->{pagecount} = int((@$articles + $pp - 1) / $pp);
  $state->{pagecount} == 0 and $state->{pagecount} = 1;
  $page <= $state->{pagecount} or $page = $state->{pagecount};

  $state->{page} = $page;
  $state->{nextpage} = $page < $state->{pagecount} ? $page + 1 : '';
  $state->{prevpage} = $page > 1 ? $page - 1 : '';
  $state->{poffset} = ($page - 1) * $pp;
  $state->{firstnumber} = 1 + $state->{poffset};
  my $end = $state->{poffset} + $pp - 1;
  $state->{lastnumber} = 1 + $end;
  $end < @$articles or $end = $#$articles;

  return [ @$articles[$state->{poffset} .. $end] ];
}

=head2 Common dynamic iterator tags

=over

=item *

I<single> I<field> - access to the fields of the current item in the
iteration.

=item *

I<single>C<_index> - the current index (zero-based) of the iteration.

=item *

I<single>C<_number> - the current number (one-based) of the iteration.

=item *

I<single>C<_count> I<...> - the number of items matched

=item *

C<if>I<Plural> I<...> - test if there are any items matched.

=item *

C<ifLast>I<Single> - test if this is the last item in the iteration.

=item *

C<ifFirst>I<Single> - test if this is the first item in the iteration.

=item *

C<next_>I<single> I<field> - retrieve values from the next item in the
iteration.

=item *

C<previous_>I<single> I<field> - retrieve values from the previous
item in the iteration.

=item *

C<ifNext>I<Single> - test if there is a next item in the iteration.

=item *

C<ifPrevious>I<Single> - test if there is a previous item in the
iteration.

=back

For article iterators only:

=over

=item *

C<move_>I<single> - in admin mode, a UI element to allow the article
to be moved up/down one position.

=back

=cut

sub _dyn_iterate_populate {
  my ($self, $state, $args, $acts, $name, $templater) = @_;

  my $method = "iter_$state->{plural}";
  my $paged = $self->_get_paged($state, \$args);
  local $self->{filter} = $self->_get_filter($state, \$args, $acts, $templater);
  my $items = $self->_do_filter
    ($state, $self->{filter}, $args, $acts, $templater, $self->$method
     ($state->{context}, $args, $acts, $templater, $state));

  return $self->_do_paged($state, $paged, $items);
}

sub _dyn_iterate_reset {
  my ($self, $state, $args, $acts, $name, $templater) = @_;

  my $rindex = $state->{rindex};
  my $rdata = $state->{rdata};
  $$rdata = $self->_dyn_iterate_populate($state, $args, $acts, $name, $templater);
  $$rindex = -1;

  $state->{previous} = undef;
  $state->{item} = undef;
  if (@$$rdata) {
    $state->{next} = $$rdata->[0];
  }
  else {
    $state->{next} = undef;
  }

  1;
}

sub _dyn_iterate {
  my ($self, $state) = @_;

  my $rindex = $state->{rindex};
  my $rdata = $state->{rdata};
  my $single = $state->{single};
  if (++$$rindex < @$$rdata) {
    $state->{previous} = $state->{item};
    $state->{item} = $state->{next};
    if ($$rindex < $#$$rdata) {
      $state->{next} = $$rdata->[$$rindex+1];
    }
    else {
      $state->{next} = undef;
    }
    $self->{req}->set_article("previous_$single" => $state->{previous});
    $self->{req}->set_article($single => $state->{item});
    $self->{req}->set_article("next_$single" => $state->{next});
    $self->{current}{$state->{plural}} = $state->{item};
    return 1;
  }
  else {
    $self->{req}->set_article($single => undef);
    $self->{current}{$state->{plural}} = undef;
    return;
  }
}

sub _dyn_item_low {
  my ($self, $item, $args) = @_;

  $item or return '';
  my $value = $item->{$args};
  defined $value 
    or return '';

  return escape_html($value);
}

sub _dyn_item {
  my ($self, $state, $args) = @_;

  my $rindex = $state->{rindex};
  my $rdata = $state->{rdata};
  my $item = $state->{item};
  unless ($state->{item}) {
    return "** $state->{single} only usable inside iterator $state->{plural} **";
  }

  return $self->_dyn_item_low($item, $args);
}

sub _dyn_next {
  my ($self, $state, $args) = @_;

  return $self->_dyn_item_low($state->{next}, $args);
}

sub _dyn_previous {
  my ($self, $state, $args) = @_;

  return $self->_dyn_item_low($state->{previous}, $args);
}

sub _dyn_item_object_low {
  my ($self, $item, $args, $state) = @_;

  $item
    or return '';
  $item->can($args)
    or return "* $args not valid for $state->{single} *";
  my $value = $item->$args;
  defined $value 
    or return '';

  return escape_html($value);
}

sub _dyn_item_object {
  my ($self, $state, $args) = @_;

  unless ($state->{item}) {
    return "** $state->{single} only usable inside iterator $state->{plural} **";
  }

  return $self->_dyn_item_object_low($state->{item}, $args, $state);
}

sub _dyn_next_obj {
  my ($self, $state, $args) = @_;

  return $self->_dyn_item_object_low($state->{next}, $args, $state);
}

sub _dyn_previous_obj {
  my ($self, $state, $args) = @_;

  return $self->_dyn_item_object_low($state->{previous}, $args, $state);
}

sub _dyn_ifNext {
  my ($self, $state) = @_;

  return defined $state->{next};
}

sub _dyn_ifPrevious {
  my ($self, $state) = @_;

  return defined $state->{previous};
}

sub _dyn_article {
  my ($self, $state, $args) = @_;

  my $rindex = $state->{rindex};
  my $rdata = $state->{rdata};
  unless ($state->{item}) {
    return "** $state->{single} only usable inside iterator $state->{plural} **";
  }

  my $item = $state->{item}
    or return '';

  return tag_article($item, $self->{req}->cfg, $args);
}

sub _dyn_next_article {
  my ($self, $state, $args) = @_;

  $state->{next} or return '';

  return tag_article($state->{next}, $self->{req}->cfg, $args);
}

sub _dyn_previous_article {
  my ($self, $state, $args) = @_;

  $state->{previous} or return '';

  return tag_article($state->{previous}, $self->{req}->cfg, $args);
}

sub _dyn_index {
  my ($self, $state) = @_;

  my $rindex = $state->{rindex};
  if ($$rindex < 0 || $$rindex >= @${$state->{rdata}}) {
    return "** $state->{single} only valid inside iterator **";
  }

  return $state->{poffset} + $$rindex;
}

sub _dyn_number {
  my ($self, $state) = @_;

  my $rindex = $state->{rindex};
  if ($$rindex < 0 || $$rindex >= @${$state->{rdata}}) {
    return "** $state->{single} only valid inside iterator **";
  }

  return $state->{poffset} + 1 + $$rindex;
}

sub _dyn_count {
  my ($self, $state, $args, $acts, $name, $templater) = @_;

  my $data = $self->_dyn_iterate_populate($state, $args, $acts, $name, $templater);

  return scalar @$data;
}

sub _dyn_if_first {
  my ($self, $rindex, $rdata) = @_;

  $$rindex == 0;
}

sub _dyn_if_last {
  my ($self, $rindex, $rdata) = @_;

  $$rindex == $#$$rdata;
}

sub dyn_iterator {
  my ($self, $plural, $single, $context, $rindex, $rdata) = @_;

  my $method = $plural;
  my $index;
  defined $rindex or $rindex = \$index;
  my $data;
  defined $rdata or $rdata = \$data;
  my %state =
    (
     plural => $plural,
     single => $single,
     rindex => $rindex,
     rdata => $rdata,
     context => $context,
     poffset => 0,
    );
  return
    (
     "iterate_${plural}_reset" =>
     [ _dyn_iterate_reset => $self, \%state ],
     "iterate_$plural" =>
     [ _dyn_iterate => $self, \%state ],
     $single => 
     [ _dyn_item => $self, \%state ],
     "${single}_index" =>
     [ _dyn_index => $self, \%state ],
     "${single}_number" =>
     [ _dyn_number => $self, \%state ],
     "${single}_count" =>
     [ _dyn_count => $self, \%state ],
     "if\u$plural" =>
     [ _dyn_count => $self, \%state ],
     "ifLast\u$single" => [ _dyn_if_last => $self, $rindex, $rdata ],
     "ifFirst\u$single" => [ _dyn_if_first => $self, $rindex, $rdata ],
     "next_$single" => [ _dyn_next => $self, \%state ],
     "previous_$single" => [ _dyn_previous => $self, \%state ],
     "ifNext\u$single" => [ _dyn_ifNext => $self, \%state ],
     "ifPrevious\u$single" => [ _dyn_ifPrevious => $self, \%state ],
    );
}

sub dyn_iterator_obj {
  my ($self, $plural, $single, $context, $rindex, $rdata) = @_;

  my $method = $plural;
  my $index;
  defined $rindex or $rindex = \$index;
  my $data;
  defined $rdata or $rdata = \$data;
  my %state =
    (
     plural => $plural,
     single => $single,
     rindex => $rindex,
     rdata => $rdata,
     context => $context,
     poffset => 0,
    );
  return
    (
     "iterate_${plural}_reset" =>
     [ _dyn_iterate_reset => $self, \%state ],
     "iterate_$plural" =>
     [ _dyn_iterate => $self, \%state ],
     $single => 
     [ _dyn_item_object => $self, \%state ],
     "${single}_index" =>
     [ _dyn_index => $self, \%state ],
     "${single}_number" =>
     [ _dyn_number => $self, \%state ],
     "${single}_count" =>
     [ _dyn_count => $self, \%state ],
     "if\u$plural" =>
     [ _dyn_count => $self, \%state ],
     "ifLast\u$single" => [ _dyn_if_last => $self, $rindex, $rdata ],
     "ifFirst\u$single" => [ _dyn_if_first => $self, $rindex, $rdata ],
     "next_$single" => [ _dyn_next_obj => $self, \%state ],
     "previous_$single" => [ _dyn_previous_obj => $self, \%state ],
     "ifNext\u$single" => [ _dyn_ifNext => $self, \%state ],
     "ifPrevious\u$single" => [ _dyn_ifPrevious => $self, \%state ],
    );
}

sub _dyn_article_move {
  my ($self, $state, $args, $acts, $func, $templater) = @_;

  $state->{parentid}
    or return '';

  return $self->tag_dynmove($state->{rindex}, $state->{rdata},
			    "stepparent=$state->{parentid}",
			    $args, $acts, $templater);
}

sub dyn_article_iterator {
  my ($self, $plural, $single, $context, $rindex, $rdata) = @_;

  my $method = $plural;
  my $index;
  defined $rindex or $rindex = \$index;
  my $data;
  defined $rdata or $rdata = \$data;
  my %state =
    (
     plural => $plural,
     single => $single,
     rindex => $rindex,
     rdata => $rdata,
     context => $context,
     poffset => 0,
    );
  $self->{context}{$plural} = $context;

  require BSE::Util::Iterate;
  my $it = BSE::Util::Iterate->new;
  return
    (
     "iterate_${plural}_reset" =>
     [ _dyn_iterate_reset => $self, \%state ],
     "iterate_$plural" =>
     [ _dyn_iterate => $self, \%state],
     $single => 
     [ _dyn_article => $self, \%state ],
     "${single}_index" =>
     [ _dyn_index => $self, \%state ],
     "${single}_number" =>
     [ _dyn_number => $self, \%state ],
     "${single}_count" =>
     [ _dyn_count => $self, \%state ],
     "if\u$plural" =>
     [ _dyn_count => $self, \%state ],
     "ifLast\u$single" => [ _dyn_if_last => $self, $rindex, $rdata ],
     "ifFirst\u$single" => [ _dyn_if_first => $self, $rindex, $rdata ],
     "next_$single" => [ _dyn_next_article => $self, \%state ],
     "previous_$single" => [ _dyn_previous_article => $self, \%state ],
     "ifNext\u$single" => [ _dyn_ifNext => $self, \%state ],
     "ifPrevious\u$single" => [ _dyn_ifPrevious => $self, \%state ],
     "move_$single" => [ _dyn_article_move => $self, \%state ],
     "${plural}_page" => [ _dyn_state => $self, \%state, "page" ],
     "${plural}_perpage" => [ _dyn_state => $self, \%state, "perpage" ],
     "${plural}_nextpage" => [ _dyn_state => $self, \%state, "nextpage" ],
     "${plural}_prevpage" => [ _dyn_state => $self, \%state, "prevpage" ],
     "${plural}_pagecount" => [ _dyn_state => $self, \%state, "pagecount" ],
     "${single}_totalcount" => [ _dyn_state => $self, \%state, "totalcount" ],
     "${plural}_firstnumber" => [ _dyn_state => $self, \%state, "firstnumber" ],
     "${plural}_lastnumber" => [ _dyn_state => $self, \%state, "lastnumber" ],
     $it->make
     (
      single => "${single}_pagec",
      plural => "${plural}_pagec",
      code => [ _dyn_iter_pages => $self, \%state ],
     ),
    );
}

sub _dyn_state {
  my ($self, $state, $name) = @_;

  return $state->{$name};
}

sub _dyn_iter_pages {
  my ($self, $state) = @_;

  my @pages;
  for my $page (1 .. $state->{pagecount}) {
    push @pages,
      {
       page => $page,
       first => $page == 1,
       last => $page == $state->{pagecount},
       current => $page == $state->{page},
       next => $page == $state->{pagecount} ? '' : $page+1,
       prev => $page == 1 ? '' : $page-1,
      };
  }

  return @pages;
}

sub get_cached {
  my ($self, $id) = @_;

  return $self->{_cache}{$id};
}

sub set_cached {
  my ($self, $id, $value) = @_;

  $self->{_cache}{$id} = $value;
}

sub _cart {
  my ($self) = @_;

  my $dyncart = $self->get_cached('cart');
  $dyncart and return $dyncart;

  my $cart = $self->{req}->session->{cart}
    or return { cart => [], total_cost => 0, total_units => 0 };

  my @cart;
  my $total_cost = 0;
  my $total_units = 0;
  for my $item (@$cart) {
    require Products;
    my $product = Products->getByPkey($item->{productId});
    my $extended = $product->price(user => scalar $self->{req}->siteuser) 
      * $item->{units};
    my $link = $product->link;
    $link =~ /^\w+:/ 
      or $link = $self->{req}->cfg->entryErr('site', 'url') . $link;
    push @cart,
      {
       ( map { $_ => $product->{$_} } $product->columns ),
       %$item,
       extended => $extended,
       link => $link,
      };
    $total_cost += $extended;
    $total_units += $item->{units};
  }
  my $result = 
    {
     cart => \@cart,
     total_cost => $total_cost,
     total_units => $total_units,
    };
  $self->set_cached(cart => $result);

  return $result;
}

1;

