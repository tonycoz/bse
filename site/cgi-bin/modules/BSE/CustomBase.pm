package BSE::CustomBase;
use strict;

sub new {
  my ($class, %params) = @_;

  exists $params{cfg} or die "No cfg parameter passed to custom class constructor";

  return bless \%params, $class;
}

sub enter_cart {
  my ($class, $items, $products, $state, $cfg) = @_;

  return 1;
}

sub cart_actions {
  my ($class, $acts, $items, $products, $state, $cfg) = @_;

  return ();
}

sub checkout_actions {
  my ($class, $acts, $items, $products, $cfg) = @_;

  return ();
}

sub checkout_update {
  my ($class, $q, $items, $products, $state, $cfg) = @_;
}

sub order_save {
  my ($class, $cgi, $order, $items, $products, $custom, $cfg) = @_;

  return 1;
}

sub total_extras {
  my ($class, $cart, $state, $cfg) = @_;

  0;
}

sub recalc {
  my ($class, $q, $items, $products, $state, $cfg) = @_;
}

sub required_fields {
  my ($class, $q, $state, $cfg) = @_;

  qw(name1 name2 address city postcode country telephone email);
}

sub purchase_actions {
  my ($class, $acts, $items, $products, $state, $cfg) = @_;

  return;
}

sub order_mail_actions {
  my ($class, $acts, $order, $items, $products, $state, $cfg) = @_;

  return ();
}

sub base_tags {
  my ($class, $articles, $acts, $article, $embedded, $cfg) = @_;

  return ();
}

# called to validate fields for a custom application
#   $cfg - a BSE::Cfg object
#   $new - the new data to be stored
#   $old - the existing article if any
#   $type - the type of article (Article, Product, Catalog)
#   $errors - hashref of fields to messages
# Return non-zero if all fields are valid.
# Set an error message in $errors for any invalid fields
sub article_validate {
  my ($self, $new, $old, $type, $errors) = @_;

  1;
}

sub article_fill_new {
  my ($self, $data, $type) = @_;

  $self->article_fill($data, $data, $type);
}

sub article_fill_old {
  my ($self, $out, $in, $type) = @_;

  $self->article_fill($out, $in, $type);
}

sub article_fill {
  my ($self, $out, $in, $type) = @_;

  1;
}

sub siteusers_changed {
  my ($self, $cfg) = @_;

  1;
}

sub siteuser_auth {
  my ($self, $session, $cgi, $cfg) = @_;

  return;
}

sub can_user_see_wishlist {
  my ($self, $wishlist_user, $current_user, $req) = @_;

  1;
}

my @dont_touch = 
  qw(id userId password confirmed confirmSecret waitingForConfirmation flags affiliate_name previousLogon);
my %dont_touch = map { $_ => 1 } @dont_touch;
  
sub siteuser_required {
  my ($self, $req) = @_;

  require SiteUsers;
  my $cfg = $req->cfg;
  my @required = qw(email);
  push @required, grep $cfg->entry('site users', "require_$_", 0),
    grep !$dont_touch{$_}, SiteUser->columns;

  return @required;
}

sub siteuser_add_required {
  my ($self, $req) = @_;

  return $self->siteuser_required($req);
}

sub siteuser_edit_required {
  my ($self, $req, $user) = @_;

  return $self->siteuser_required($req);
}

1;

=head1 NAME

  BSE::CustomBase - base class for the customization class.

=head1 SYNOPSIS

  package BSE::Custom;
  use base 'BSE::CustomBase';

  ... implement overridden functions ...

=head1 DESCRIPTION

This class provides basic implementations of various methods of
BSE::Custom.

The aim is that if extra customization methods are created, you can
upgrade everything but BSE::Custom, and your code will still work.

Current methods that can be implemented in BSE::Custom are:

=over

=item checkout_actions($acts, $items, $products, $state, $cgi)

Return a list of extra "actions" or members of the %acts hash used for
converting the checkout template to the final output.  Used to define
extra tags for the checkout page.

=item checkout_update($cgi, $items, $products, $state, $cfg)

This is called by the checkupdate target of shop.pl, which does
nothing else.

=item order_save($cgi, $order, $items, $products, $custom, $cfg)

Called immediately before the order is saved.  You can perform extra
validation and die() with an error message describing the problem, or
perform extra data manipulation.

=item BSE::Custom->enter_cart($q, $items, $products, $state)

Called just before the cart is displayed.

=item BSE::Custom->cart_actions($acts, $items, $products, $state)

Defines tags available in the cart.

=item BSE::Custom->total_extras($item, $products, $state)

Extras that should be added to the total.  You should probably define
extra tags in cart_actions() and purchase_actions() to display the
extra data.

=item BSE::Custom->recalc($q, $items, $products, $state)

Called when a recalc is done.  Useful for storing form values into the
state.

=item BSE::Custom->required_field($q, $state)

Called to get the fields required for checkout.  You might want to add
or remove them, depending on the products bought.

=item BSE::Custom->purchase_actions($acts, $items, $products, $state)

Defines extra tags for use on the checkout page.

=item BSE::Custom->base_tags($articles, $acts, $article, $embedded)

Defines extra tags for use on any page.

=item BSE::Custom->siteusers_changed($cfg)

Called when a change is made to the site users table.

=item $self->siteuser_save($user, $req)

Called at the beginning of the save_opts() action.

=item send_session_cookie($cookie_name, $session, $sessionid)

Called whenever the session cookie is set.

=item siteuser_add($user, $who, $cfg)

Called when a new user is created.  $user is the user object, $who is
'user' for registration, 'admin' for added by the admin.

=item siteuser_edit($user, $who, $cfg)

Called when changes to a user are saved.  $user is the user object,
$who is 'user' for user saving options, 'admin' for changes made by
the admin, or 'import' if a file of users was imported.

=item group_add_member($group, $user_id, $cfg)

Called when a user is added to a group.  $group is the group object,
$user_id is the numeric id of the user.

=item group_remove_member($group, $user_id, $cfg)

Called when a user is removed from a group.  $group is the group
object, $user_id is the numeric id of the user.

=back

=cut
