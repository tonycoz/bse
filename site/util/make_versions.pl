#!perl -w
use strict;
use ExtUtils::Manifest qw(maniread);
use File::Slurp;
use Digest::MD5;

my $files = maniread;

my $outname = shift
  or die "Usage: $0 outfilename\n";

my @files = sort grep /cgi-bin.*\.pm/, keys %$files;

@files = grep !m(BSE/(Modules|Version)\.pm$), @files;

my %versions;

my $md5 = Digest::MD5->new;

for my $file (@files) {
  my $content = read_file($file);

  my $module = $file;
  $module =~ s(^site/cgi-bin/modules/(.*)\.pm$)($1)
    or die "Can't convert $file to module\n";
  $module =~ s(/)(::)g;

  $content =~ /^our \$VERSION = "([0-9.]+)";/m
    or die "No version found in $file\n";

  $versions{$module} = $1;

  $md5->add("$module=$1\n");
}

my %data_versions;
my @data_files = sort grep m(data/db/.*\.data$), keys %$files;
for my $file (@data_files) {
  my $content = read_file($file);
  
  (my $inst_name = $file) =~ s(^site/data/)()
    or die "Can't convert $file to installed name\n";
  $content =~ /^\s*\#\s*VERSION=\s*([0-9.]+)/m
    or die "No version found in $file\n";

  $data_versions{$inst_name} = $1;

  $md5->add("$inst_name=$1\n");
}

my $hash = $md5->hexdigest;

open my $out, ">", $outname
  or die "Cannot create $outname: $!\n";

print $out <<EOS;
package BSE::Modules;
use strict;

# automatically generated

our \$hash = "$hash";

our %versions =
  (
EOS

for my $module (sort keys %versions) {
  print $out qq/  "$module" => "$versions{$module}",\n/;
}

print $out <<EOS;
  );

our %file_versions =
  (
EOS

for my $file (sort keys %data_versions) {
  print $out qq/  "$file" => "$data_versions{$file}",\n/;
}

print $out <<EOS
  );

1;
EOS
