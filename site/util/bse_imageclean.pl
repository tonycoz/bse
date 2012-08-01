#!perl -w
use strict;
use Getopt::Long;
use FindBin;
use Encode;

Getopt::Long::Configure('bundling');
my $verbose;
my $actions;
my $nothing;
my $bse_dir = "../cgi-bin";
my $help;
GetOptions
  (
   "v", \$verbose,
   "a|actions" => \$actions,
   "b|bse=s" => \$bse_dir,
   "n|nothing" => \$nothing,
   "h" => \$help,
  );

if ($help) {
  print <<EOS;
Usage: perl $0 [options]
Options:
 -n - only display the actions to perform, but make no changes
      (displays items as "skipped")
 -a - display the actions as their done
 -b cgidir - locate the BSE CGI directory (default ../cgi-bin)
 -v - display progress as tables and directories are scanned
 -h - display this help text

Invocation without options will silently remove orphan image objects
and files.
EOS
  exit 0;
}

unshift @INC, "$bse_dir/modules";

require BSE::Console;

my $req = BSE::Console->new(cgidir => $bse_dir);

$nothing and ++$actions;

require BSE::ImageClean;

my $action = $nothing ? "skip" : "remove";

my $msgbase = "msg:bse/admin/imageclean";

BSE::ImageClean->scan
  (
   sub {
     my $state = shift;
     if ($verbose) {
       if ($state->{type} eq "stage") {
	 print $req->catmsg("$msgbase/stage/$state->{stage}", [], $state->{stage}), "\n";
       }
       elsif ($state->{type} eq "substage") {
	 print "  ", $req->catmsg("$msgbase/substage/$state->{stage}/$state->{substage}", [], $state->{substage}), "\n";
       }
     }

     if ($state->{type} eq "orphanimage") {
       print "    ", $req->catmsg("$msgbase/process/${action}image", [ $state->{image}->id, $state->{image}->image ]), "\n"
	 if $verbose || $actions;
       $state->{image}->remove unless $nothing;
     }
     elsif ($state->{type} eq "orphanfile") {
       print "    ", $req->catmsg("$msgbase/process/${action}file", [ $state->{file} ]), "\n"
	 if $verbose || $actions;
       unlink $state->{fullfile} unless $nothing;
     }
   }
  );

exit;

=head1 NAME

bse_imageclean.pl - clean up image objects and files

=head1 SYNOPSIS

  # clean up images silently
  perl bse_imageclean.pl

  # clean up images verbosely
  perl bse_imageclean.pl -v

  # clean up images indicating work done (no headings)
  perl bse_imageclean.pl -a

  # summarize what will be done cleaning up images
  # implies -a
  perl bse_imageclean.pl -n

=head1 DESCRIPTION

C<bse_imageclean.pl> is a command-line tool to clean up image objects
and the image file directory.

You can supply a C<-v> option to produce progress output.  This output
assumes your terminal encoding matches the BSE configured character
encoding.

The C<-a> option only displays the work lines from the C<-v> output,
this can be used in a C<cron> job to alert you if file have been left
orphan (since cron only sends email if there's output.)

You can supply a C<-n> option to display vebose output without doing
the actual clean up, this implies C<-a>.

=head1 AUTHOR

Tony Cook <tony@develop-help.com>

=head1 SEE ALSO

imageclean.pl, BSE::ImageClean, BSE::UI::AdminImageClean

=cut
