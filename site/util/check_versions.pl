#!perl -w
use strict;

my %vers;

my @check = `git status -s`;
chomp @check;
@check = sort grep /cgi-bin\/.*\.pm$/, @check;
@check = grep !m(BSE/(Modules|Version)\.pm), @check;
my @errors;
for my $check (@check) {
  $check =~ /^D/ and next;
  $check =~ s/^(..)\s+//;
  $check =~ s/.* -> //; # renames
  my $type = $1;
  -e $check or die "Cannot find file $check\n";

  my $ver = file_vers($check);

  if ($type =~ "M") {
    my $committed = `git show HEAD:$check`;
    my $old_ver = content_vers($committed);

    if (defined $old_ver) {
      $old_ver eq $ver
	and push @errors, "Version not updated in $check\n";
    }
  }
}

@errors and die @errors;

sub file_vers {
  my ($filename) = @_;

  open my $file, "<", $filename
    or die "Cannot open $filename; $!\n";
  my $content = do { local $/; <$file> };
  close $file;

  my $vers = content_vers($content)
    or die "No version found in $filename\n";

  return $vers;
}

sub content_vers {
  my ($lines) = @_;

  $lines =~ /^our \$VERSION = "([0-9.]+)";/m
    or return;

  return $1;
}
