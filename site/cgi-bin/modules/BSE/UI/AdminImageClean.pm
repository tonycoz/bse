package BSE::UI::AdminImageClean;
use strict;
use base qw(BSE::UI::AdminDispatch);
use BSE::ImageClean;

our $VERSION = "1.000";

my %actions =
  (
   intro => "bse_imageclean",
   preview => "bse_imageclean",
   final => "bse_imageclean",
  );

sub actions { \%actions }

sub rights { \%actions }

sub default_action { "intro" }

sub req_intro {
  my ($self, $req) = @_;

  my %acts = $req->admin_tags;
  return $req->dyn_response("admin/imageclean/intro", \%acts);
}

sub _split_page {
  my ($self, $req, $template) = @_;

  my %acts = $req->admin_tags;
  my $temp_result = $req->response($template, \%acts);
  my ($prefix, $per_message, $suffix) =
    split /<:\s*iterator\s+(?:begin|end)\s+messages\s*:>/, $temp_result->{content};

  my $charset = $req->cfg->charset;
  print "Content-Type: ", $temp_result->{type}, "\n";
  print "\n";
  print $prefix;

  return ($per_message, $suffix);
}

sub req_preview {
  my ($self, $req) = @_;

  my ($per_message, $suffix) = $self->_split_page($req, "admin/imageclean/preview");

  my %acts = $req->admin_tags;
  ++$|;

  BSE::ImageClean->scan
      (
       sub {
	 my ($state) = @_;
	 $req->set_variable(state => $state);
	 $acts{state} = [ \&tag_hash, $state ];
	 print BSE::Template->replace($per_message, $req->cfg, \%acts, $req->{vars});
       }
      );
  print $suffix;
  return;
}

sub req_final {
  my ($self, $req) = @_;

  my ($per_message, $suffix) = $self->_split_page($req, "admin/imageclean/final");

  my %acts = $req->admin_tags;
  ++$|;

  my %files = map { $_ => 1 } $req->cgi->param("file");
  my %images = map { $_ => 1 } $req->cgi->param("image");

  BSE::ImageClean->scan
      (
       sub {
	 my ($state) = @_;
	 my $acted = 0;
	 if ($state->{type} eq "orphanimage") {
	   $acted = exists $images{$state->{image}->id};
	   $state->{image}->remove if $acted;
	 }
	 elsif ($state->{type} eq "orphanfile") {
	   $acted = exists $files{$state->{file}};
	   unlink $state->{fullfile} if $acted;
	 }
	 $req->set_variable(state => $state);
	 $req->set_variable(acted => $acted);
	 $acts{state} = [ \&tag_hash, $state ];
	 print BSE::Template->replace($per_message, $req->cfg, \%acts, $req->{vars});
       }
      );
  print $suffix;
  return;
}

__END__

=head1 NAME

imageclean.pl - clean up the images directory and image records

=head1 SYNOPSIS

 (called as a CGI script, no values passed in)

=head1 WARNING

This will remove B<any> images in the configured managed images
directory that have names starting with 8 or more digits if
they don't exist in the C<image> table as a record with a current
article number.

If you need image names of this form, put them elsewhere, or
reconfigure the managed images directory.

=head1 DESCRIPTION

Scans the C<image> table looking for images that don't have an
article, and for image files that don't have image records.

The first is required due to a bug in older versions that left the
image records around when deleting an article.  It's also a recovery
tool just in case the database loses referential integrity, since
MySQL doesn't enforce it.

The second is required for two reasons:

=over

=item

older versions didn't remove the image files when images were removed

=item

you may have deleted articles with images under an older version,
which would have left the image records (and the image files)

=back

=head1 AUTHOR

Tony Cook <tony@develop-help.com>

=cut
