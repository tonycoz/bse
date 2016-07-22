package BSE::Storage::AmazonS3;
use strict;
use BSE::Storage::Base;
our @ISA = qw(BSE::Storage::Base);
use Net::Amazon::S3;
use Carp qw(confess);

our $VERSION = "1.001";

sub new {
  my ($class, %opts) = @_;

  my $self = $class->SUPER::new(%opts);

  my $cfg = $self->cfg;
  for my $key (qw/baseurl keyid accesskey bucket/) {
    $self->{$key} = $self->configure($key);
    defined $self->{$key}
      or confess "Missing $key from configuration";
  }
  $self->{prefix} = $self->configure('prefix', '');
  $self->{host} = $self->configure('host', 's3.amazonaws.com');

  return $self;
}

sub _connect {
  my $self = shift;

  my $conn = Net::Amazon::S3->new
    (
     {
      aws_access_key_id => $self->{keyid},
      aws_secret_access_key => $self->{accesskey},
      host => $self->{host},
     }
    );

  my $bucket = $conn->bucket($self->{bucket});

  return ( $conn, $bucket );
}

sub store {
  my ($self, $local_name, $basename, $http_extras) = @_;

  #print STDERR "store($local_name, $basename)\n";

  my ($conn, $bucket) = $self->_connect;
  my %headers = %$http_extras;
  $headers{acl_short} = "public-read";
  $bucket->add_key_filename($self->{prefix} . $basename, $local_name, 
			    \%headers)
    or die "Cannot add file $local_name as $basename to S3: ", 
      $bucket->errstr, "\n";

  return $self->{baseurl} . $basename;
}

sub unstore {
  my ($self, $basename) = @_;

  my ($conn, $bucket) = $self->_connect;
  my $success = $bucket->delete_key($self->{prefix} . $basename);

  return $success;
}

sub list {
  my ($self) = @_;

  my ($conn, $bucket) = $self->_connect;
  use Data::Dumper;
  my $result = $bucket->list_all({ prefix => $self->{prefix} });
  my @keys = map $_->{key}, @{$result->{keys}};
  for my $key (@keys) {
    $key =~ s/^\Q$self->{prefix}//;
  }

  return @keys;
}

sub url {
  my ($self, $basename) = @_;

  $self->{baseurl} . $basename;
}

sub cmd {
  my ($self, $cmd, @args) = @_;

  if ($cmd eq 'create') {
    my ($conn) = $self->_connect;
    if ($conn->add_bucket( 
			  { 
			   bucket => $self->{bucket},
			   acl_short => 'public-read' 
			  } 
			 )) {
      print "Bucket $self->{bucket} created\n";
    }
    else {
      die "Could not create bucket $self->{bucket}: ", $conn->errstr;
    }
  }
  elsif ($cmd eq 'delete') {
    my ($conn, $bucket) = $self->_connect;
    if ($bucket->delete_bucket) {
      print "Bucket $self->{bucket} deleted\n";
    }
    else {
      die "Could not delete bucket $self->{bucket}: ", $conn->errstr, "\n";
    }
  }
  elsif ($cmd eq 'listbuckets') {
    my ($conn) = $self->_connect;
    my $buckets = $conn->buckets;
    print $_->bucket, "\n" for @{$buckets->{buckets}};
  }
  elsif ($cmd eq 'help') {
    print <<EOS;
Usage: $0 storage command
Possible commands:
  create - the create the bucket for the given storage
  delete - delete the bucket for the given storage
  listbuckets - list the buckets for the account of the given storage
  help - display this help
EOS
  }
}

1;

=head1 NAME

BSE::Storage::AmazonS3 - storage that stores via Amazon S3.

=head1 SYNOPSIS

  [s3images]
  class=BSE::Storage::AmazonS3
  baseurl=http://yourisp.com/images/
  keyid=...
  accesskey=...
  bucket=ftppassword
  cond=...
  host=...

=head1 DESCRIPTION

This is a BSE storage that accesses the remote store via Amazon S3.

C<host> must be set to the end-point matching the location of the
bucket, see:

  http://docs.aws.amazon.com/general/latest/gr/rande.html#s3_region

for details.  Defaults to C<s3.amazonaws.com> if not set.

=cut
