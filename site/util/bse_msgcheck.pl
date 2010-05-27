#!perl -w
use strict;
use FindBin;
use lib "$FindBin::Bin/../cgi-bin/modules";
use BSE::API qw(bse_init);
use File::Find;
use BSE::MessageScanner;

bse_init("../cgi-bin");

@ARGV
  or die "Usage: $0 directory ...\n";

# scan for message ids in files under each tree given
my %id_reported;
my @ids = BSE::MessageScanner->scan(\@ARGV);
my $last_filename = '';
my $errors = 0;
for my $entry (@ids) {
  my ($id, $file, $lineno) = @$entry;
  $id_reported{$id} and next;
  (my $subid = $id) =~ s/^msg://;
  my ($detail) = BSE::DB->query(bseMessageDetail => $subid);
  my ($def) = BSE::DB->query(bseMessageDefaults => $subid);
  if ($detail) {
    unless ($def) {
      print "$file:$lineno:$id - no default entry\n";
      ++$errors;
      $id_reported{$id} = 1;
    }
  }
  else {
    print "$file:$lineno: $id - no base entry\n";
    ++$errors;
    $id_reported{$id} = 1;
  }
}
