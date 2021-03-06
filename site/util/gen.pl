#!perl -w
use strict;
use Getopt::Long;
use FindBin;
use lib "$FindBin::Bin/../cgi-bin/modules";
use BSE::Regen qw/generate_all generate_article generate_base pregenerate_list generate_one_extra/;
use BSE::API qw(bse_init bse_cfg);
use BSE::TB::Articles;

bse_init("../cgi-bin");

Getopt::Long::Configure('bundling');
my $verbose;
my $article;
GetOptions("v", \$verbose);
$verbose = defined $verbose;

my $cfg = bse_cfg();

my $articles = 'BSE::TB::Articles';

$| = 1;

if (@ARGV) {
  Squirrel::Table->caching(1);
  my @extras_cache;
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
	generate_base(cfg => $cfg, 
		      progress => $verbose ? sub { print $_[1], "\n" } : undef);
      }
      elsif ($id =~ /^extra:(.*)$/) {
	my $name = $1;

	@extras_cache = pregenerate_list($cfg)
	  unless @extras_cache;

	my @extras;
	if ($name =~ m(^/(.*)/$)) {
	  my $re_text = $1;
	  my $re = eval { qr/$re_text/ }
	    or die "Could not compile re /$re_text/: $@";
	  @extras = grep $_->{name} =~ $re, @extras_cache
	    or print "$re_text matched no extras\n";
	}
	else {
	  @extras = grep $_->{name} eq $name, @extras_cache
	    or print "Cannot find extra $name\n";
	}
	for my $extra (@extras) {
	  print "  $extra->{name}\n" if $verbose;
	  generate_one_extra($articles, $extra);
	}
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

  # generate only article 10, verbosely
  perl gen.pl -v 10

  # generate extras and base pages
  perl gen.pl extras

  # generate a specific extra
  perl gen.pl extra:search.tmpl

  # generate a set of matching extras
  perl gen.pl extra:/^checkout/

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
