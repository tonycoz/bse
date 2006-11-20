package BSE::CfgInfo;
use strict;

use vars qw(@ISA @EXPORT_OK);
require Exporter;
@ISA = qw(Exporter);
@EXPORT_OK = qw(custom_class admin_base_url cfg_image_dir credit_card_class product_options);

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

  my $local_inc = $cfg->entry('paths', 'libraries');
  unshift @INC, $local_inc if $local_inc;

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

sub cfg_image_dir {
  my ($cfg) = @_;

  $cfg->entry('paths', 'images', $Constants::IMAGEDIR);
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

  my $local_inc = $cfg->entry('paths', 'libraries');
  unshift @INC, $local_inc if $local_inc;

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

1;

__END__

=back

=head1 AUTHOR

Tony Cook <tony@develop-help.com>

=cut
