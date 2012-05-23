#!perl -w
use strict;
use Test::More;

BEGIN {
  eval <<EOS
use Imager;
use Imager::File::PNG;
use Imager::File::GIF;
use Imager::File::JPEG;
1;
EOS
    or plan skip_all => "Imager or a needed file module not installed";
}

use BSE::Thumb::Imager;
use Imager::Test qw(is_image_similar);

my @dimension_tests =
  ( # input geo, width, height, type, output width, height, type
   [ "scale(100x100)", 200, 100, "", 100, 50, "" ],
   [ "scale(100x100,fill:808080)", 200, 100, "", 100, 100, "" ],
   [ "scale(100x100c)", 150, 80, "", 100, 80, "" ],
   [ "scale(100x100c)", 150, 110, "", 100, 100, "" ],
  );

my @image_tests =
  (
   # geo, input, reference output, max diff (def: 1000)
   [ "scale(40x30)", "simple.png", "scale40x30.png" ],
   [ "scale(40x30,fill:808080)", "simple.png", "scale40x30fill.png" ],
  );

plan tests => 8 + 3 * @dimension_tests + 4 * @image_tests;

my $cfg = bless
  {
  }, "Test::Cfg";

my $th = BSE::Thumb::Imager->new($cfg);
ok($th, "make driver object");

{ # parsing
  my $error;
  ok($th->validate_geometry("scale(100x)", \$error),
     "validate scale(100x)");
  ok($th->validate_geometry("scale(100x100)", \$error),
     "validate scale(100x100)");
  ok($th->validate_geometry("scale(x100)", \$error),
     "validate scale(x100)");
  ok($th->validate_geometry("scale(100x100c)", \$error),
     "validate scale(100x100c)");
  ok($th->validate_geometry("scale(100x100,fill:808080)", \$error),
     "validate scale(100x100,fill:808080)");
  ok(!$th->validate_geometry("scale(100x,fill:808080)", \$error),
     "fail validate scale(100x,fill:808080)");
  is($error, "scale:Both dimensions must be supplied for fill",
     "check error message");
}

{ # dimensions
  for my $test (@dimension_tests) {
    my ($geo, $in_w, $in_h, $in_type, $out_w, $out_h, $out_type) = @$test;

    my $name = "$geo/$in_w/$in_h";
    my ($result_w, $result_h, $result_type) =
      $th->thumb_dimensions_sized($geo, $in_w, $in_h, $in_type);
    is($result_w, $out_w, "dim $name: check output width");
    is($result_h, $out_h, "dim $name: check output height");
    is($result_type, $out_type, "dim $name: check output type");
  }
}

{ # image results
  for my $test (@image_tests) {
    my ($geo, $infile, $reffile, $maxdiff) = @$test;

    defined $maxdiff or $maxdiff = 1000;

    my $name = "$geo/$infile";

  SKIP:
    {
      my $error;
      my ($data, $type) =
	$th->thumb_data(filename => "t/thumb/data/$infile",
			geometry => $geo,
			error => \$error);
      ok($data, "$name: made a thumb")
	or skip("no thumb data to check", 3);

      my $outim = Imager->new;
      ok($outim->read(data => $data),
	 "$name: get the image data back as an image")
	or skip("can't compare an image I can't read", 2);
      my $refim = Imager->new;
      ok($refim->read(file => "t/thumb/data/$reffile"),
	 "$name: get the reference image file as an image")
	or skip("can't compare an image I can't read", 1);
      is_image_similar($outim, $refim, $maxdiff,
		       "$name: compare");
    }
  }
}

package Test::Cfg;

sub entry {
  my ($self, $section, $key, $default) = @_;

  $section eq "imager thumb driver"
    or return $default;
  $self->{$key}
    and return $self->{$key};
  return $default;
}
