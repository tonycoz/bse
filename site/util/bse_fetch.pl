#!perl -w
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../cgi-bin/modules";
use Getopt::Long;
use BSE::API qw(bse_init bse_cfg);
use BSE::Util::Fetcher;

our $VERSION = "1.000";

bse_init("../cgi-bin");

my $verbose;
my $nosave;
my $nolog;
my $section = "automatic data";
GetOptions(
	   "v:i" => \$verbose,
	   "nosave|n" => \$nosave,
	   "nolog" => \$nolog,
	   "section|s=s" => \$section,
	  );
if (defined $verbose && $verbose eq '') {
  $verbose = 1;
}

my $cfg = bse_cfg();

my @extra;
if (@ARGV) {
  @extra = ( articles => [ @ARGV ] );
}

my $o = BSE::Util::Fetcher->new
  (
   cfg => $cfg,
   verbose => $verbose,
   save => !$nosave,
   log => !$nolog,
   section => $section,
   @extra,
  );

$o->run();

my $errors = $o->errors;
print STDERR "$_->[0]: $_->[1]\n" for @$errors;

exit 1 if @$errors;

=head1 NAME

bse_fetch.pl - fetch data based on article metadata and store as article metadata

=head1 SYNOPSIS

  perl bse_fetch.pl

=head1 DESCRIPTION

The C<bse_fetch.pl> tool, based on configuration stored in the
C<[automatic data]> section of the configuration file and on the
article metadata that describes, retrieves data from remote sources
and stores it in article metadata.

Since this mechanism accesses external sites it will only function if
access control is enabled.

At the simplest configuring this requires setting one key in
C<[automatic data]>:

  [automatic data]
  data_example=example

and defining a field for the URL in C<[global article metadata]>:

  [global article metadata]
  example_url=

  [article metadata example_url]
  title=Example URL
  type=string
  width=60

If an article has this metadata set, typically via the article editor,
a run of C<bse_fetch.pl> will attempt to fetch the URL defined by that
metadata.

The value of the URL metadata must contain at least one non-blank
character or it will be silently skipped.

You can set a C<< url_patternI<suffix> >> to allow the supplied value
to be subtituted into a full url, so for example:

  [automatic data]
  data_example=example
  url_pattern_example=http://example.com/location/$s/events
  url_escape_example=1

  [global article metadata]
  example_url=

  [article metadata example_url]
  title=Events location ID
  type=string
  width=10

The C<< url_escapeI<suffix> >> key allows the value from the URL field
to be URL escaped.  If this field is a full URL or URL fragment you
typically don't want this, but if it's some sort of text to be
subtituted into a URL it's recommended.

The final URLs must have one of C<http:>, C<https:> or C<ftp:> scheme.
C<file:> URLs are not permitted.

By default the content retrived must have a JSON content type and must
validate as JSON, you can control this with the C<< validateI<suffix>
>> and C<< typesI<suffix> >> keys.  The first specifies a regular
expression used to validate the returned content type, while the
second can be set to C<none> to disable validation of the content
itself.

  [automatic downloads]
  data_example=example
  ; accept anything
  types_example=.
  validate_example=none

To prevent storage of excessively large content, by default C<<
max_lengthI<suffix> >> to 1000000, which you can set lower or higher
as needed.  There is no mechanism to support unlimited sizes.

By default, if a fetch of the data for a particular article fails, any
existing stored metadata for that definition is deleted from the
article.  You can prevent that by setting C<< on_failI<suffix> >> to
C<keep>.

If a fetch fails, an error is reported in the audit log.

Success however is silent by default, you can configure success
producing an C<info> audit log message by setting C<<
on_successI<suffix> >> to C<log>:

  [automatic downloads]
  data_example=example
  on_success_example=log

=head AUTHOR

Tony Cook <tony@develop-help.com>

=cut
