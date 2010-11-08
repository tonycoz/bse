package BSE::FileEditor;
use strict;
use BSE::Util::Tags;
use Constants qw($TMPLDIR $IMAGES_URI);
use BSE::TB::ArticleFiles;
use BSE::Util::HTML;
use Util qw/refresh_to/;

our $VERSION = "1.000";

=head1 NAME

  BSE::FileEditor - maintains a list of files associated with an article

=head1 SYNOPSIS

  if (BSE::FileEditor->process_files($session, $cgi)) {
     # nothing else to do
  }

=head1 DESCRIPTION

Note: unlike the image editor you need to create the article before
starting to edit the file list, and changes take place immediately.

=cut

my @actions = qw/filelist fileadd fileswap filedel filesort filesave/;

sub new {
  my ($class, %opts) = @_;

  $opts{session}
    or die "No session supplied";
  $opts{cfg}
    or die "No config supplied";
  $opts{backopts}
    or die "No backopts supplied";
  $opts{cgi}
    or die "No cgi supplied";

  bless \%opts, $class;
}  

sub process_files {
  my ($self) = @_;

  my $id = $self->{cgi}->param('id');
  $id or return 0;
  my $article = Articles->getByPkey($id);
  $article or return 0;

  for my $action (@actions) {
    if ($self->{cgi}->param($action)) {
      $self->$action($article);
      return 1;
    }
  }

  return 0;
}

sub filelist {
  my ($self, $article) = @_;

  my @files = $self->_getfiles($article);

  my $blank = qq!<img src="$IMAGES_URI/trans_pixel.gif" width="17" height="13" border="0" align="absbottom" />!;

  my $message = $self->{cgi}->param('message') || '';
  my $file_index;
  my %acts;
  %acts =
    (
     article=>sub { escape_html($article->{$_[0]}) },
     BSE::Util::Tags->make_iterator(\@files, 'file', 'files', \$file_index),
     BSE::Util::Tags->basic(\%acts),
     BSE::Util::Tags->admin(\%acts, $self->{cfg}),
     message => sub { escape_html($message) },
     move =>
     sub {
       my $html = '';
       @files > 1 or return '';
       if ($file_index > 0) {
	 $html .= <<HTML;
<a href="$ENV{SCRIPT_NAME}?fileswap=1&id=$article->{id}&file1=$files[$file_index]{id}&file2=$files[$file_index-1]{id}"><img src="$IMAGES_URI/admin/move_up.gif" width="17" height="13" border="0" alt="Move Up" align="absbottom"></a>
HTML
       }
       else {
	 $html .= $blank;
       }
       if ($file_index < $#files) {
	 $html .= <<HTML;
<a href="$ENV{SCRIPT_NAME}?fileswap=1&id=$article->{id}&file1=$files[$file_index]{id}&file2=$files[$file_index+1]{id}"><img src="$IMAGES_URI/admin/move_down.gif" width="17" height="13" border="0" alt="Move Down" align="absbottom"></a>
HTML
       }
       else {
	 $html .= $blank;
       }
       $html;
     },
    );

  $self->show_page('filelist', \%acts);
}

my %types =
  (
   qw(
   pdf  application/pdf
   txt  text/plain
   htm  text/html
   html text/html
   gif  image/gif
   jpg  image/jpeg
   jpeg image/jpeg
   doc  application/msword
   rtf  application/rtf
   zip  application/zip
   png  image/png
   bmp  image/bmp
   tif  image/tiff
   tiff image/tiff
   sgm  text/sgml
   sgml text/sgml
   xml  text/xml
   mov  video/quicktime
   )
  );

sub _refresh_list {
  my ($self, $article) = @_;

  my $urlbase = $self->{cfg}->entryVar('site', 'url');
  my $url = $urlbase . $ENV{SCRIPT_NAME} . "?id=$article->{id}&filelist=1";
  refresh_to($url);
}

sub fileadd {
  my ($self, $article) = @_;

  for my $key ($self->{cgi}->param()) {
    print STDERR "$key => ",$self->{cgi}->param($key),"\n";
  }

  my %file;
  
  my @cols = BSE::TB::ArticleFile->columns;
  shift @cols;
  for my $col (@cols) {
    if (defined $self->{cgi}->param($col)) {
      $file{$col} = $self->{cgi}->param($col);
    }
  }
  
  $file{forSale} = 0 + exists $file{forSale};
  $file{articleId} = $article->{id};
  $file{download} = 0 + exists $file{download};
  $file{requireUser} = 0 + exists $file{requireUser};

  my $downloadPath = $self->{cfg}->entryVar('paths', 'downloads');

  # build a filename
  my $file = $self->{cgi}->param('file');
  unless ($file) {
    $self->{cgi}->param(message=>"Enter or select the name of a file on your machine");
    return $self->filelist($article);
  }
  if (-z $file) {
    $self->{cgi}->param(message=>"File is empty");
    return $self->filelist($article);
  }

  unless ($file{contentType}) {
    unless ($file =~ /\.([^.]+)$/) {
      $file{contentType} = "application/octet-stream";
    }
    unless ($file{contentType}) {
      my $ext = lc $1;
      my $type = $types{$ext};
      unless ($type) {
	$type = $self->{cfg}->entry('extensions', $ext)
	  || $self->{cfg}->entry('extensions', ".$ext")
	    || "application/octet-stream";
      }
      $file{contentType} = $type;
    }
  }
  
  my $basename = '';
  $file =~ /([\w.-]+)$/ and $basename = $1;

  my $filename = time. '_'. $basename;

  # for the sysopen() constants
  use Fcntl;

  # loop until we have a unique filename
  my $counter="";
  $filename = time. '_' . $counter . '_' . $basename 
    until sysopen( OUTPUT, "$downloadPath/$filename", 
		   O_WRONLY| O_CREAT| O_EXCL)
      || ++$counter > 100;

  fileno(OUTPUT) or die "Could not open file: $!";

  # for OSs with special text line endings
  binmode OUTPUT;

  my $buffer;

  no strict 'refs';

  # read the image in from the browser and output it to our output filehandle
  print OUTPUT $buffer while read $file, $buffer, 8192;

  # close and flush
  close OUTPUT
    or die "Could not close file $filename: $!";

  use BSE::Util::SQL qw/now_datetime/;
  $file{filename} = $filename;
  $file{displayName} = $basename;
  $file{sizeInBytes} = -s $file;
  $file{displayOrder} = time;
  $file{whenUploaded} = now_datetime();

  my $fileobj = BSE::TB::ArticleFiles->add(@file{@cols});

  $self->_refresh_list($article);
}

sub fileswap {
  my ($self, $article) = @_;

  my $id1 = $self->{cgi}->param('file1');
  my $id2 = $self->{cgi}->param('file2');

  if ($id1 && $id2) {
    my @files = $self->_getfiles($article);
    
    my ($file1) = grep $_->{id} == $id1, @files;
    my ($file2) = grep $_->{id} == $id2, @files;
    
    if ($file1 && $file2) {
      ($file1->{displayOrder}, $file2->{displayOrder})
	= ($file2->{displayOrder}, $file1->{displayOrder});
      $file1->save;
      $file2->save;
    }
  }

  $self->_refresh_list($article);
}

sub filedel {
  my ($self, $article) = @_;

  my $fileid = $self->{cgi}->param('file');
  if ($fileid) {
    my @files = $self->_getfiles($article);

    my ($file) = grep $_->{id} == $fileid, @files;

    if ($file) {
      my $downloadPath = $self->{cfg}->entryErr('paths', 'downloads');
      my $filename = $downloadPath . "/" . $file->{filename};
      my $debug_del = $self->{cfg}->entryBool('debug', 'file_unlink', 0);
      if ($debug_del) {
	unlink $filename
	  or print STDERR "Error deleting $filename: $!\n";
      }
      else {
	unlink $filename;
      }
      $file->remove();
    }
  }

  $self->_refresh_list($article);
}

sub filesave {
  my ($self, $article) = @_;

  my @files = $self->_getfiles($article);

  for my $file (@files) {
    if (defined $self->{cgi}->param("description_$file->{id}")) {
      $file->{description} = $self->{cgi}->param("description_$file->{id}");
      if (my $type = $self->{cgi}->param("contentType_$file->{id}")) {
	$file->{contentType} = $type;
      }
      $file->{download} = 0 + defined $self->{cgi}->param("download_$file->{id}");
      $file->{forSale} = 0 + defined $self->{cgi}->param("forSale_$file->{id}");
      $file->{requireUser} = 0 + defined $self->{cgi}->param("requireUser_$file->{id}");
      $file->save;
    }
  }

  $self->_refresh_list($article);
}

sub show_page {
  my ($self, $template, $acts) = @_;

  my $base = $self->{cfg}->entry('paths', 'admin_templates') 
    || $TMPLDIR."/admin";
  my $file = $self->{cfg}->entry('admin templates', $template) || "$template.tmpl";

  my $obj = Squirrel::Template->new(template_dir => $base);

  my $type = "text/html";
  my $charset = $self->{cfg}->entry('html', 'charset');
  $charset = 'iso-8859-1' unless defined $charset;
  $type .= "; charset=$charset";

  print "Content-Type: $type\n\n";
  print $obj->show_page($base, $file, $acts);
}

sub _getfiles {
  my ($self, $article) = @_;

  return sort { $b->{displayOrder} <=> $a->{displayOrder} }
    BSE::TB::ArticleFiles->getBy(articleId=>$article->{id});
}

1;
