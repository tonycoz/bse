package BSE::Cfg;
use strict;
use base "DevHelp::Cfg";
use Carp qw(confess);
use constant MAIN_CFG => 'bse.cfg';

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

1;

=head1 AUTHOR

Tony Cook <tony@develop-help.com>

=cut
