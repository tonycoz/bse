#!perl -w
use strict;
use Test::More tests => 7;

use_ok("BSE::Importer");
use_ok("BSE::Importer::Target::Base");
use_ok("BSE::Importer::Source::Base");
use_ok("BSE::Importer::Target::Article");
use_ok("BSE::Importer::Target::Product");
SKIP: {
  eval "require Spreadsheet::ParseExcel;"
    or skip "Cannot load Spreadsheet::ParseExcel", 1;
  use_ok("BSE::Importer::Source::Base");
}
SKIP: {
  eval "require Text::CSV;"
    or skip "Cannot load Text::CSV", 1;
  use_ok("BSE::Importer::Source::CSV");
}

