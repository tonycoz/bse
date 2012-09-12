package BSE::CfgInfo;
use strict;

our $VERSION = "1.003";

use vars qw(@ISA @EXPORT_OK);
require Exporter;
@ISA = qw(Exporter);
@EXPORT_OK = qw(custom_class admin_base_url cfg_image_dir cfg_image_uri cfg_dist_image_uri cfg_data_dir cfg_scalecache_dir cfg_scalecache_uri credit_card_class product_options bse_default_country);

=head1 NAME

BSE::CfgInfo - functions that return information derived from configuration

=head1 SYNOPSIS

  my $cfg = BSE::Cfg->new;
  use BSE::CfgInfo 'admin_base_url';
  my $admin_base = admin_base_url($cfg);

  use BSE::CfgInfo 'custom_class';
  my $class = custom_class($cfg);

  use BSE::CfgInfo 'credit_card_class';
  my $class = credit_card_class($cfg);

  use BSE::CfgInfo 'product_options';
  my $options = product_options($cfg);

  use BSE::CfgInfo 'bse_default_country';
  my $country = bse_default_country($cfg);

=head1 DESCRIPTION

This module contains functions which examine the BSE configuration and
return information useful at the application level.

=over

=item custom_class

Returns an object of the class of the configured custom class.

=cut

sub custom_class {
  my ($cfg) = @_;

  local @INC = @INC;

  my $class = $cfg->entry('basic', 'custom_class', 'BSE::Custom');
  (my $file = $class . ".pm") =~ s!::!/!g;

  _do_local_inc($cfg);

  require $file;

  return $class->new(cfg=>$cfg);
}

=item admin_base_url($cfg)

=cut

sub admin_base_url {
  my ($cfg) = @_;

  my $base = $cfg->entryIfVar('site', 'adminurl');
  unless ($base) {
    my $sec_admin = $cfg->entryBool('site', 'secureadmin', 0);
    if ($sec_admin) {
      $base = $cfg->entryErr('site', 'secureurl');
    }
    else {
      $base = $cfg->entryErr('site', 'url');
    }
  }

  return $base;
}

=item cfg_image_dir()

Return the directory configured for storage of managed images.

=cut

sub cfg_image_dir {
  my ($cfg) = @_;

  $cfg ||= BSE::Cfg->single;

  return $cfg->entryIfVar('paths', 'images', $Constants::IMAGEDIR);
}

=item cfg_image_uri()

Return the configured base URI for managed images.

This should correspond to the directory specified by [paths].images

Configured with [uri].images

=cut

sub cfg_image_uri {
  my ($cfg) = @_;

  $cfg ||= BSE::Cfg->single;

  require Constants;
  return $cfg->entryIfVar('uri', 'images', $Constants::IMAGES_URI);
}

=item cfg_dist_image_uri()

Return the configured base URI for images distributed with BSE.

This imcludes images such as F<trans_pixel.gif> and C<admin/error.gif>.

Must not include a trailing C</>.

Configured with [uri].dist_images

=cut

sub cfg_dist_image_uri {
  my ($cfg) = @_;

  $cfg ||= BSE::Cfg->single;

  return $cfg->entryIfVar('uri', 'dist_images', "/images");
}

=item cfg_data_dir()

Returns the directory configured for storage of files such as
F<stopwords.txt>.

Configured with [paths].data

=cut

sub cfg_data_dir {
  my ($cfg) = @_;

  $cfg ||= BSE::Cfg->single;

  my $dir = $cfg->entryIfVar('paths', 'data', $Constants::DATADIR);
  -d $dir
    or die "[paths].data value '$dir' isn't a directory\n";

  return $dir;
}

=item cfg_scalecache_dir()

Returns the directory configured for storage of generated thumbnails.

Controlled with [paths].scalecache.

Default: C<cfg_image_dir() . "/scaled">

=cut

sub cfg_scalecache_dir {
  my ($cfg) = @_;

  $cfg ||= BSE::Cfg->single;

  my $dir = $cfg->entryIfVar('paths', 'scalecache', cfg_image_dir($cfg) . "/scaled");
  -d $dir
    or die "[paths].scalecache value '$dir' isn't a directory\n";

  return $dir;
}

=item cfg_scalecache_uri()

Returns the uri for the directory configured for storage of generated
thumbnails.

Controlled with C<[uri].scalecache> with a fallback to
C<[paths].scalecacheurl>.

=cut

sub cfg_scalecache_uri {
  my ($cfg) = @_;

  $cfg ||= BSE::Cfg->single;

  my $uri = $cfg->entryIfVar('uri', 'scalecache');
  defined $uri
    or $uri = $cfg->entryIfVar('path', 'scalecacheurl');
  defined $uri
    or $uri = cfg_image_uri($cfg) . "/scaled";

  return $uri;
}

=item credit_card_class

Loads the configured credit card class and instantiates it.

=cut

sub credit_card_class {
  my ($cfg) = @_;

  local @INC = @INC;

  my $class = $cfg->entry('shop', 'cardprocessor')
    or return;
  (my $file = $class . ".pm") =~ s!::!/!g;

  _do_local_inc($cfg);

  require $file;

  return $class->new($cfg);
}

=item product_options

Returns a hashref of product options, where the key is the option id,
the values are each a hashref with the following keys:

=over

=item *

desc - description of the option

=item *

values - array ref of possible values for the option

=item *

labels - hashref of labels for the different values.  This is always
filled out with the labels defaulting to the values.

=back

=cut

sub product_options {
  my ($cfg) = @_;

  my %options = %Constants::SHOP_PRODUCT_OPTS;

  my %cfg_opts = $cfg->entriesCS('shop product options');
  for my $option (keys %cfg_opts) {
    my ($option_desc, @values) = split /;/, $cfg_opts{$option};
    my %value_labels;
    for my $value (@values) {
      $value_labels{$value} = $cfg->entry("shop product option $option",
					  $value, $value);
    }
    $options{$option} =
      {
       desc => $option_desc,
       values => \@values,
       labels => \%value_labels,
      };
  }

  \%options;
}

sub bse_default_country {
  my ($cfg) = @_;

  return $cfg->entry("basic", "country", "Australia");
}

sub _do_local_inc {
  my ($cfg) = @_;

  my $local_inc = $cfg->entryIfVar('paths', 'libraries');

  unshift @INC, $local_inc if $local_inc;
}

1;

__END__

=back

=head1 AUTHOR

Tony Cook <tony@develop-help.com>

=cut
