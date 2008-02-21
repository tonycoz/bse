package BSE::Util::DynamicTags;
use strict;
use BSE::Util::Tags qw(tag_article);
use DevHelp::HTML;
use base 'BSE::ThumbLow';

sub new {
  my ($class, $req) = @_;
  return bless { req => $req }, $class;
}

sub tags {
  my ($self) = @_;
  
  my $req = $self->{req};
  return
    (
     BSE::Util::Tags->basic(undef, $req->cgi, $req->cfg),
     user => [ \&tag_user, $req ],
     ifUser => [ \&tag_ifUser, $req ],
     ifUserCanSee => [ \&tag_ifUserCanSee, $req ],
     $self->dyn_article_iterator('dynlevel1s', 'dynlevel1'),
     $self->dyn_article_iterator('dynlevel2s', 'dynlevel2'),
     $self->dyn_article_iterator('dynlevel3s', 'dynlevel3'),
     $self->dyn_article_iterator('dynallkids_of', 'dynofallkid'),
     $self->dyn_article_iterator('dynchildren_of', 'dynofchild'),
     $self->dyn_iterator('dyncart', 'dyncartitem'),
     $self->dyn_article_iterator('wishlist', 'wishlistentry', $req),
     url => [ tag_url => $self ],
     dyncarttotalcost => [ tag_dyncarttotal => $self, 'total_cost' ],
     dyncarttotalunits => [ tag_dyncarttotal => $self, 'total_units' ],
     ifAncestor => 0,
     ifUserMemberOf => [ tag_ifUserMemberOf => $self ],
     dthumbimage => [ tag_dthumbimage => $self ],
     dyntarget => [ tag_dyntarget => $self ],
    );
}

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

sub tag_user {
  my ($req, $args) = @_;

  my $siteuser = $req->siteuser
    or return '';

  exists $siteuser->{$args}
    or return '';

  escape_html($siteuser->{$args});
}

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

sub tag_dyntarget {
  my ($self, $args, $acts, $func, $templater) = @_;

  my $req = $self->{req};

  my ($script, $target, @options) = DevHelp::Tags->get_parms($args, $acts, $templater);

  for my $option (@options) {
    $option = unescape_html($option);
  }

  return escape_html($req->user_url($script, $target, @options));
}

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

sub iter_dynallkids_of {
  my ($self, $unused, $args, $acts, $templater) = @_;

  my @ids = map { split } DevHelp::Tags->get_parms($args, $acts, $templater);
  for my $id (@ids) {
    unless ($id =~ /^\d+$|^-1$/) {
      $id = $self->{req}->get_article($id);
    }
  }
  @ids = grep defined && /^\d+$|^-1$/, @ids;

  require Articles;
  return $self->access_filter(map Articles->all_visible_kids($_), @ids);
}

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

sub iter_dyncart {
  my ($self, $unused, $args) = @_;

  my $cart = $self->_cart
    or return [];

  return $cart->{cart};
}

sub tag_dyncarttotal {
  my ($self, $field, $args) = @_;

  my $cart = $self->_cart
    or return 0;

  return $cart->{$field};
}

sub iter_wishlist {
  my ($self, $req) = @_;

  my $user = $req->siteuser
    or return [];
  return [ $user->wishlist ];
}

sub access_filter {
  my ($self, @articles) = @_;

  my $req = $self->{req};

  my $admin_sees_all = $req->cfg->entry('basic', 'admin_sees_all', 1);

  $admin_sees_all && $self->{admin} and 
    return \@articles;

  return [ grep $req->siteuser_has_access($_), @articles ];
}

my $cols_re; # cache for below

sub _get_filter {
  my ($self, $rargs) = @_;

  if ($$rargs =~ s/filter:\s+(.*)\z//s) {
    my $expr = $1;
    my $orig_expr = $expr;
    unless ($cols_re) {
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

    return $filter;
  }
  else {
    return;
  }
}

sub _do_filter {
  my ($self, $filter, $articles) = @_;

  $filter
    or return $articles;

  return [ grep $filter->($_), @$articles ];
}

sub _dyn_iterate_reset {
  my ($self, $rdata, $rindex, $plural, $context, $args, $acts, $name, 
      $templater) = @_;

  my $method = "iter_$plural";
  my $filter = $self->_get_filter(\$args);
  $$rdata = $self->
    _do_filter($filter, $self->$method($context, $args, $acts, $templater));
  
  $$rindex = -1;

  1;
}

sub _dyn_iterate {
  my ($self, $rdata, $rindex, $single) = @_;

  if (++$$rindex < @$$rdata) {
    $self->{req}->set_article($single => $$rdata->[$$rindex]);
    return 1;
  }
  else {
    $self->{req}->set_article($single => undef);
    return;
  }
}

sub _dyn_item {
  my ($self, $rdata, $rindex, $single, $plural, $args) = @_;

  if ($$rindex < 0 || $$rindex >= @$$rdata) {
    return "** $single only usable inside iterator $plural **";
  }

  my $item = $$rdata->[$$rindex]
    or return '';
  my $value = $item->{$args};
  defined $value 
    or return '';

  return escape_html($value);
}

sub _dyn_article {
  my ($self, $rdata, $rindex, $single, $plural, $args) = @_;

  if ($$rindex < 0 || $$rindex >= @$$rdata) {
    return "** $single only usable inside iterator $plural **";
  }

  my $item = $$rdata->[$$rindex]
    or return '';

  return tag_article($item, $self->{req}->cfg, $args);
}

sub _dyn_index {
  my ($self, $rindex, $rdata, $single) = @_;

  if ($$rindex < 0 || $$rindex >= @$$rdata) {
    return "** $single only valid inside iterator **";
  }

  return $$rindex;
}

sub _dyn_number {
  my ($self, $rindex, $rdata, $single) = @_;

  if ($$rindex < 0 || $$rindex >= @$$rdata) {
    return "** $single only valid inside iterator **";
  }

  return 1 + $$rindex;
}

sub _dyn_count {
  my ($self, $rdata, $rindex, $plural, $context, $args, $acts, $name, 
      $templater) = @_;

  my $method = "iter_$plural";
  my $data = $self->$method($context, $args, $acts, $templater);

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
  return
    (
     "iterate_${plural}_reset" =>
     [ _dyn_iterate_reset => $self, $rdata, $rindex, $plural, $context ],
     "iterate_$plural" =>
     [ _dyn_iterate => $self, $rdata, $rindex, $single, $context ],
     $single => 
     [ _dyn_item => $self, $rdata, $rindex, $single, $plural ],
     "${single}_index" =>
     [ _dyn_index => $self, $rindex, $rdata, $single ],
     "${single}_number" =>
     [ _dyn_number => $self, $rindex, $rdata ],
     "${single}_count" =>
     [ _dyn_count => $self, $rindex, $rdata, $plural, $context ],
     "if\u$plural" =>
     [ _dyn_count => $self, $rindex, $rdata, $plural, $context ],
     "ifLast\u$single" => [ _dyn_if_last => $self, $rindex, $rdata ],
     "ifFirst\u$single" => [ _dyn_if_first => $self, $rindex, $rdata ],
    );
}

sub dyn_article_iterator {
  my ($self, $plural, $single, $context, $rindex, $rdata) = @_;

  my $method = $plural;
  my $index;
  defined $rindex or $rindex = \$index;
  my $data;
  defined $rdata or $rdata = \$data;
  return
    (
     "iterate_${plural}_reset" =>
     [ _dyn_iterate_reset => $self, $rdata, $rindex, $plural, $context ],
     "iterate_$plural" =>
     [ _dyn_iterate => $self, $rdata, $rindex, $single, $context ],
     $single => 
     [ _dyn_article => $self, $rdata, $rindex, $single, $plural ],
     "${single}_index" =>
     [ _dyn_index => $self, $rindex, $rdata, $single ],
     "${single}_number" =>
     [ _dyn_number => $self, $rindex, $rdata ],
     "${single}_count" =>
     [ _dyn_count => $self, $rindex, $rdata, $plural, $context ],
     "if\u$plural" =>
     [ _dyn_count => $self, $rindex, $rdata, $plural, $context ],
     "ifLast\u$single" => [ _dyn_if_last => $self, $rindex, $rdata ],
     "ifFirst\u$single" => [ _dyn_if_first => $self, $rindex, $rdata ],
    );
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
    my $extended = $product->{retailPrice} * $item->{units};
    my $link = $product->{link};
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

1;

=head1 NAME

BSE::Util::DynamicTags - basic dynamic page tags

=head1 REFERENCE

=over

=item dthumbimage article geometry image field

=item dthumbimage article geometry image

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

=back

=cut
