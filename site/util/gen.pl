#!perl -w
use strict;
use Getopt::Long;
use FindBin;
use lib "$FindBin::Bin/../cgi-bin/modules";
use Util qw/generate_all generate_article/;
use BSE::API qw(bse_init bse_cfg);
use Articles;

bse_init("../cgi-bin");

Getopt::Long::Configure('bundling');
my $verbose;
my $article;
GetOptions("v", \$verbose);
$verbose = defined $verbose;

my $cfg = bse_cfg();

my $articles = 'Articles';

$| = 1;

if (@ARGV) {
  Squirrel::Table->caching(1);
  print "Generating @ARGV\n" if $verbose;
  for my $articleid (@ARGV) {
    my ($start, $end);
    if ($articleid =~ /^(\d+)-(\d+)$/) {
      ($start, $end) = ($1, $2);
    }
    else {
      $start = $end = $articleid;
    }
    for my $id ($start..$end) {
      if ($id =~ /^\d+$/) {
	my $article = $articles->getByPkey($id);
	if ($article) {
	  print "Article $id\n" if $verbose;
	  eval {
	    generate_article($articles, $article, $cfg);
	  };
	  $@ and print "Error: $@\n";
	}
	else {
	  print "Could not load article $id\n";
	}
      }
      elsif ($id eq 'extras') {
	Util::generate_extras($articles, $cfg, 
			      $verbose ? sub { print $_[0], "\n" } : undef);
      }
    }
  }
}
else {
  print "Generating all\n" if $verbose;
  if ($verbose) {
    generate_all($articles, $cfg,  sub { print $_[0],"\n"; });
  }
  else {
    generate_all($articles, $cfg);
  }
}
print "Done\n" if $verbose;
exit;

=head1 NAME

gen.pl - generate all or part of the site from the command-line

=head1 SYNOPSIS

  # generate the whole site, silently
  perl gen.pl

  # generate the whole site, with progress
  perl gen.pl -v

  # generate articles 100 through 200 and 300 through 400
  perl gen.pl 100-200 300-400

  # generate extras and base pages
  perl gen.pl extras

=head1 DESCRIPTION

gen.pl regenerates specific articles, the static and base pages, or
the whole site from the command-line.

gen.pl is suitable for use from a cron job.

If the C<-v> option is present gen.pl will produce information about
where it is in it's processing.

If there are no arguments beyond C<-v> gen.pl will regenerate the
whole site.

Otherwise you can supply a list of article numbers, ranges or
C<extras> to regenerate the given articles, articles within the range
or the extra base pages.

=head1 AUTHOR

Tony Cook <tony@develop-help.com>

=head1 SEE ALSO

bse

=cut
