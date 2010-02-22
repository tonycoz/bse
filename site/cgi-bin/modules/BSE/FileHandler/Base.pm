package BSE::FileHandler::Base;
use strict;
use Carp qw(confess);

=head1 NAME

BSE::FileHandler::Base - base class for file handlers

=head1 SYNOPSIS

  my $fh = BSE::FileHandler::XXX->new($cfg);

  # for derived classes to define:
  my $cfg_section = $fh->section;
  eval {
    $fh->process_file($file);
  };
  my $html = $fh->inline($file, $parameters);
  my $content = $fh->metacontent($file, $meta_name);
  my @fields = $fh->metametadata;

  # for derived classes to use:
  my $cfg = $fh->cfg;
  my $value = $fh->cfg_entry("key", $default);

=head1 METHODS

=over

=item $class->new($cfg)

Create a new file handler object.

This is not connected to a single file, but should construct quickly.

$cfg must be a BSE::Cfg compatible object.

=cut

sub new {
  my ($class, $cfg) = @_;

  $cfg
    or confess "Missing cfg option";

  return bless
    {
     cfg => $cfg,
    }, $class;
}

=item $obj->cfg

Returns the $cfg value supplied to new().

=cut

sub cfg {
  $_[0]{cfg};
}

=item $obj->cfg_entry($key)

=item $obj->cfg_entry($key, $default)

Retrieve a single configuration value from the $cfg object supplied to
new.

Uses the section name returned by the section method, which the
derived class must define.

=cut

sub cfg_entry {
  my ($self, $key, $def) = @_;

  return $self->cfg->entry($self->section, $key, $def);
}

=item $obj->process_file($file)

Attempt to detect the type and extract metadata from the file
specified by $file, a BSE::TB::ArticleFile object.

If there is an error while extracting metadata, die with a message.

=cut

sub process_file {
  my ($self, $file) = @_;

  my $class = ref $self;
  confess "$class hasn't implemented process-file";
}

=item $obj->inline($file, $parameters)

Called when handling:

  <:filen - fieldname:>
  <:filen name fieldname:>

or:

  file[id]
  file[id|fieldname]

where the $parameters field is set to fieldname.

Only called when $parameters isn't "link", "meta.I<name>" or a field
name found in an file record.

The default implementation uses a template under the meta/ directory,
constructed as:

  meta/I<prefix>_I<metaname>

where I<prefix> is the result of the metaprefix method.

=item $obj->metacontent($file, $meta_name)

Return generated meta data.

=cut

sub metacontent {
  my ($self, $file, $meta_name) = @_;

  require BSE::Template;
  my %meta = map { $_->name => $_->value }
    grep $_->content_type eq "text/plain", $file->metadata;

  my @prefix = ( $self->metaprefix, "base" );
  my $template;
  my $found;
  for my $prefix (@prefix) {
    $template = "meta/${prefix}_$meta_name";
    $found = BSE::Template->find_source($template)
      and last;
  }
  unless ($found) {
    return
      {
       headers =>
       [
	"Status: 404",
	"Content-Type: text/plain",
       ],
       content =>
       "No metadata template meta/prefix_name found"
      };
  }

  my %acts =
    (
     BSE::Util::Tags->static(undef, $self->cfg),
     meta => [ \&tag_hash, \%meta ],
     file => [ \&tag_hash, $file ],
     src => scalar(escape_html($file->url($self->cfg))),
    );

  return BSE::Template->get_response($template, $self->cfg, \%acts);
}

=item $obj->metametadata

Return descriptions of the metadata set by $obj->process file.

Should return a list of hashes, each hash can have the following keys:

=over

=item *

name - the name of the metadata item (required).  Note: for image
types this should be the base name of the metadata, without the
_data/_width/_height suffix.

=item *

title - a descriptive name of the metadata item

=item *

type - one of "integer", "real", "image", "string", "text", "enum".
If enum, I<values> should be set.  If string, I<size> should be set.

=item *

unit - text to display after the field, typically a unit of measure or
a format display.

=item *

rules - validation rules as per DevHelp::Validate.

=item *

help - extended help text formatted as HTML

=back

=cut

sub metametadata {
  return;
}

1;

