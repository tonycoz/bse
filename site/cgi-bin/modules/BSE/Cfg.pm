package BSE::Cfg;
use strict;
use base "DevHelp::Cfg";
use Carp qw(confess);
use constant MAIN_CFG => 'bse.cfg';

our $VERSION = "1.005";

my %cache;

my $single;

=head1 NAME

  BSE::Cfg - configuration file for BSE

=head1 SYNOPSIS

  my $cfg = BSE::Cfg->new();
  my $entry1 = $cfg->entry($section, $key); # undef on failure
  my $entry2 = $cfg->entryErr($section, $key); # abort on failure
  my $entry3 = $cfg->entryVar($section, $key); # replace variables in value

=head1 DESCRIPTION

Provides a simple configuration file object for BSE.

Currently just provides access to a single config file, but could
later be modified to provide access to one based on the current site,
for use in a mod_perl version of BSE.

=head1 METHODS

=over

=item BSE::Cfg->new

Create a new configuration file object.

Parameters:

=over

=item *

path - the path to start searching for the config file in, typically
the BSE cgi-bin.

=back

=cut

sub new {
  my ($class, %opts) = @_;

  $single = $class->SUPER::new(filename => MAIN_CFG, %opts);

  return $single;
}

=item single

Return the BSE configuration object.

This is used to avoid always passing around a config object.

=cut

sub single {
  my ($class) = @_;

  $single or confess "BSE's configuration hasn't been initialized yet";

  return $single;
}

=item utf8

Return a true value if BSE is working in UTF-8 internal mode.

=cut

sub utf8 {
  return $single->entry("basic", "utf8", 0);
}

=item charset

Return the BSE character set.

=cut

sub charset {
  return $single->entry('html', 'charset', 'iso-8859-1');
}

=item user_url($script, $target)

=cut

sub user_url {
  my ($cfg, $script, $target, @options) = @_;

  my $secure = $script =~ /^(shop|user)$/;
  $secure = $cfg->entry("secure user url", $script, $secure);
  my $base;
  my $template;
  if ($target) {
    if ($script eq 'nuser') {
      $template = "/cgi-bin/nuser.pl/user/TARGET";
    }
    else {
      $template = "/cgi-bin/$script.pl?a_TARGET=1";
    }
    $template = $cfg->entry('targets', $script, $template);
    $template =~ s/TARGET/$target/;
  }
  else {
    if ($script eq 'nuser') {
      $template = "/cgi-bin/nuser.pl/user";
    }
    else {
      $template = "/cgi-bin/$script.pl";
    }
    $template = $cfg->entry('targets', $script.'_n', $template);
  }
  if (@options) {
    my @entries;
    while (my ($key, $value) = splice(@options, 0, 2)) {
      require BSE::Util::HTML;
      if ($key eq '-base') {
	$base = $value;
      }
      else {
	push @entries, "$key=" . BSE::Util::HTML::escape_uri($value);
      }
    }
    if (@entries) {
      $template .= $template =~ /\?/ ? '&' : '?';
      $template .= join '&', @entries;
    }
  }

  $base ||= $secure ? $cfg->entryVar('site', 'secureurl') : '';

  return $base . $template;
}

sub admin_url {
  my ($self, $action, $params, $name) = @_;

  return $self->admin_url2($action, undef, $params, $name);
}

sub admin_url2 {
  my ($self, $action, $target, $params, $name) = @_;

  require BSE::CfgInfo;
  my $add_target;
  my $url = BSE::CfgInfo::admin_base_url($self);
  if ($self->entry("admin url", $action)) {
    $url .= $self->entry("admin url", $action);
    $url .= "/" . $target if $target;
  }
  elsif ($self->entry("admin controllers", $action)) {
    $url .= $self->entry("site", "adminscript", "/cgi-bin/admin/bseadmin.pl");
    $url .= "/" . $action;
    $url .= "/" . $target if $target;
  }
  elsif ($self->entry("nadmin controllers", $action)) {
    $url .= "/cgi-bin/admin/nadmin.pl/$action";
    $url .= "/$target" if $target;
  }
  else {
    $url .= "/cgi-bin/admin/$action.pl";
    $add_target++ if $target;
  }
  if ($add_target) {
    $params ||= {};
    $params = { %$params, "a_$target" => 1 };
  }
  if ($params && keys %$params) {
    require BSE::Util::HTML;
    $url .= "?" . join("&", map { "$_=".BSE::Util::HTML::escape_uri($params->{$_}) } keys %$params);
  }
  $url .= "#$name" if $name;

  return $url;
}

=item content_base_path()

Site document root.  Previously $Constants::CONTENTBASE.

=cut

sub content_base_path {
  my ($self) = @_;

  ref $self
    or $self = $self->single;

  my $path = $self->entryIfVar("paths", "public_html");
  unless ($path) {
    # backward compatibility
    require Constants;
    $path = $Constants::CONTENTBASE;
  }

  return $path;
}

1;

=head1 AUTHOR

Tony Cook <tony@develop-help.com>

=cut
