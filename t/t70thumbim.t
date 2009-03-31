#!perl -w
use strict;
use Test::More tests => 4;

my $cfg = bless 
  {
   "imager thumb driver" =>
   {
    #debug => 1,
   }
  }, "Test::Cfg";

BEGIN { use_ok("BSE::Thumb::Imager") }

my $thumb = BSE::Thumb::Imager->new($cfg);

{
  my ($width, $height, $type, $orig) =
    $thumb->thumb_dimensions_sized("scale(55x55c)", 300, 300, undef);
  is($width, 55, "check scale 55x55c width");
  is($height, 55, "check scale 55x55c width");
  is($type, undef, "check type");
}

package Test::Cfg;

sub entry {
  my ($self, $section, $key, $default) = @_;

  if (exists $self->{$section}
      && exists $self->{$section}{$key}) {
    return $self->{$section}{$key};
  }

  return $default;
}
