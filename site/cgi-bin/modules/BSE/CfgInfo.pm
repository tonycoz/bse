package BSE::CfgInfo;
use strict;

use vars qw(@ISA @EXPORT_OK);
require Exporter;
@ISA = qw(Exporter);
@EXPORT_OK = qw(custom_class admin_base_url cfg_image_dir credit_card_class);

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

=head1 DESCRIPTION

This module contains functions which examine the BSE configuration and
return information useful at the application level.

=over

=item admin_base_url($cfg)

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

1;

__END__

=back

=head1 AUTHOR

Tony Cook <tony@develop-help.com>

=cut
