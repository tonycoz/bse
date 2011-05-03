package BSE::TB::File;
use strict;
use Squirrel::Row;
use BSE::ThumbCommon;
use vars qw/@ISA/;
@ISA = qw/Squirrel::Row BSE::ThumbCommon/;
use Carp 'confess';

our $VERSION = "1.003";

sub columns {
  return qw/id file_type owner_id filename display_name content_type
            size_in_bytes when_uploaded is_public name display_order src
	    category alt width height url description ftype/;
}

sub table {
  "bse_files";
}

my $display_order = time;
sub defaults {
  require BSE::Util::SQL;
  return
    (
     when_uploaded => BSE::Util::SQL::now_datetime(),
     is_public => 0,
     name => '',
     display_order => $display_order++,
     src => '',
     category => '',
     alt => '',
     width => 0,
     height => 0,
     url => '',
     ftype => "img",
    );
}

sub full_filename {
  my ($self) = @_;

  $self->is_public ? $self->public_filename : $self->private_filename;
}

sub private_filename {
  my ($self) = @_;

  my $downloadPath = BSE::TB::Files->private_path;
  return $downloadPath . "/" . $self->filename;
}

sub public_filename {
  my ($self) = @_;

  my $downloadPath = BSE::TB::Files->public_path;
  return $downloadPath . "/" . $self->filename;
}

sub remove {
  my ($self) = @_;

  my $filename = $self->full_filename;
  my $debug_del = BSE::Cfg->single->entryBool('debug', 'file_unlink', 0);
  if ($debug_del) {
    unlink $filename
      or print STDERR "Error deleting $filename: $!\n";
  }
  else {
    unlink $filename;
  }

  $self->SUPER::remove();
}

sub url {
  my ($self) = @_;

  if ($self->is_public) {
    return $self->public_url;
  }
  else {
    return $self->file_behaviour->file_url($self);
  }
}

sub public_url {
  my ($self) = @_;

  return BSE::TB::Files->public_base_url() . $self->filename;
}

my %behaviours;

sub file_behaviour {
  my ($self) = @_;

  my $behaviour = $behaviours{$self->file_type};

  unless ($behaviour) {
    my ($cfg) = BSE::Cfg->single->entry("file behaviour", $self->file_type);
    my ($class, $load, $method) = split /,/, $cfg;
    $load ||= $class;
    $method ||= "new";

    $load =~ s(::)(/)g;
    $load .= ".pm" unless $load =~ /\.pm$/;

    require $load;

    $behaviour = $class->$method;
    $behaviours{$self->file_type} = $behaviour;
  }

  return $behaviour;
}

sub json_data {
  my ($self) = @_;

  my $data = $self->data_only;

  return $data;
}

sub dynamic_thumb_url {
  my ($self, %opts) = @_;

  my $geo = delete $opts{geo}
    or Carp::confess("Missing geo parameter");

  return "/cgi-bin/thumb.pl?s=file&g=$geo&image=$self->{id}";
}

1;
