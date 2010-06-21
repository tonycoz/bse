package BSE::MessageScanner;
use strict;
use File::Find;

=item BSE::MessageScanner->scan(\@basepaths)

Scan .tmpl, .pm and .pl files under the given directories for apparent
message uses and return each use with the id, file and line number.

=cut

sub scan {
  my ($class, $bases) = @_;

  my @files;
  find
    (
     sub {
       -f && /\.(tmpl|pm|pl)$/ && push @files, $File::Find::name;
     },
     @$bases
    );
  my @ids;
  for my $file (@files) {
    open my $fh, "<", $file
      or die "Cannot open $file: $!\n";
    my $errors = 0;
    while (my $line = <$fh>) {
      my @msgs = $line =~ m(\b(msg:[\w-]+(?:/\$?[\w-]+)*));
      push @ids, map [ $_, $file, $. ], grep !/\$/, @msgs;
    }
    close $fh;
  }

  return @ids;
}

1;
