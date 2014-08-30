#!perl -w
use strict;
use Getopt::Long;
use FindBin;
use lib "$FindBin::Bin/../cgi-bin/modules";
use BSE::Index;
use BSE::API qw(bse_init bse_cfg);
use BSE::TB::Articles;
use Encode;

bse_init("../cgi-bin");

Getopt::Long::Configure('bundling');
my $verbose;
my $article;
GetOptions("v", \$verbose);
$verbose = defined $verbose;

my $cfg = bse_cfg();

my $charset = $cfg->charset;
my $cb;
if ($verbose) {
  ++$|;
  $cb = sub {
    my $text = join("", @_)."\n";
    $text = encode($charset, $text, Encode::FB_DEFAULT);
    print $text;
  };
}

my $index = BSE::Index->new
  (
   note => $cb,
   error => $cb,
  );

$index->do_index;

exit;

=head1 NAME

bse_makeindex.pl - generate the BSE search index.

=head1 SYNOPSIS

  # generate the index silently
  perl bse_makeindex.pl

  # generate the index with progress
  perl bse_makeindex.pl -v

=head1 DESCRIPTION

C<bse_makeindex.pl> is a command-line tool to regenerate the BSE
search index.

You can supply a C<-v> option to produce progress output.  This output
assumes your terminal encoding matches the BSE configured character
encoding.

=head1 HISTORY

Previously F<cgi-bin/admin/makeIndex.pl> worked in both modes, but the
indexing logic was moved to L<BSE::Index> and the command-line
specific code moved to F<bse_makeindex.pl>.

=head1 AUTHOR

Tony Cook <tony@develop-help.com>

=head1 SEE ALSO

makeIndex.pl, BSE::Index

=cut
