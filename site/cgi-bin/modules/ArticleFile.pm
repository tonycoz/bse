package ArticleFile;
use strict;
# represents a file associated with an article from the database
use Squirrel::Row;
use vars qw/@ISA/;
@ISA = qw/Squirrel::Row/;
use Carp 'confess';

sub columns {
  return qw/id articleId displayName filename sizeInBytes description 
            contentType displayOrder forSale download whenUploaded
            requireUser notes/;
}

sub remove {
  my ($self, $cfg) = @_;

  $cfg or confess "No \$cfg supplied to ",ref $self,"->remove()";

  my $downloadPath = $cfg->entryErr('paths', 'downloads');
  my $filename = $downloadPath . "/" . $self->{filename};
  my $debug_del = $cfg->entryBool('debug', 'file_unlink', 0);
  if ($debug_del) {
    unlink $filename
      or print STDERR "Error deleting $filename: $!\n";
  }
  else {
    unlink $filename;
  }
  
  $self->SUPER::remove();
}

1;
