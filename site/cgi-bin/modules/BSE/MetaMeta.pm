package BSE::MetaMeta;
use strict;
use Carp qw(confess);
use Image::Size;

our $VERSION = "1.002";

=head1 NAME

BSE::MetaMeta - information about metadata.

=head1 SYNOPSIS

  my @metainfo = $class->all_metametadata;
  ...

=head1 INSTANCE METHODS

=over

=cut

my %meta_rules;

my %rule_map =
  (
   image => "image",
   integer => "integer",
   string => "dh_one_line",
   real => "real",
   enum => "meta_enum", # generated
  );

my %field_defs =
  (
   image =>
   {
    htmltype => "file",
   },
   string =>
   {
    htmltype => "text",
    width => 60,
   },
   text =>
   {
    htmltype => "textarea",
    width => 60,
    height => 20,
   },
   integer =>
   {
    htmltype => "text",
    width => 8,
   },
   real =>
   {
    htmltype => "text",
    width => 10,
   },
   enum =>
   {
    htmltype => "select",
   },
  );

=item name

The field name of the metadata.

=cut

sub name { $_[0]{name} }

=item type

The type of the metadata.

=cut

sub type { $_[0]{type} }

=item title

The display name of the metadata.

=cut

sub title { $_[0]{title} }

=item rules

The validation rules for the metadata.

=cut

sub rules { @{$_[0]{rules}} }

=item values

The permitted values for the metadata for enum types.

=cut

sub values { @{$_[0]{values}} }

=item labels

The display labels as a list.

=cut

sub labels { @{$_[0]{labels}} }

=item htmltype

How to display this field.  May be ignored depending on C<type>.

=cut

sub htmltype { $_[0]{htmltype} }

=item width

Display width.  May be ignored depending on C<type>.

=cut

sub width { $_[0]{width} }

=item height

Display height.  May be ignored depending on C<type>.

=cut

sub height { $_[0]{height} }

=item ro

Whether this field is read-only.

=cut

sub ro { $_[0]{ro} }

=item unit

Unit of measurement of this field (for display only)

=cut

sub unit { $_[0]{unit} }

=item is_text

True if this is representable as text.

=cut

sub is_text {
  $_[0]{type} ne "image";
}

=item cond

True if the field should be prompted for if not present.

=cut

sub cond {
  my ($self, $file) = @_;

  return $self->{cond}->($file);
}

=item field

Return a hash suitable as the validation parameter for the field (and
for template field formatting).

=cut

sub field {
  my ($self) = @_;

  my %field =
    (
     %{$field_defs{$self->type}},
     description => scalar $self->title,
     units => scalar $self->unit,
     rules => scalar $self->rules,
     type => scalar $self->type,
     htmltype => scalar $self->htmltype,
    );
  if ($self->type =~ /^(?:multi)?enum$/) {
    my $values = [ $self->values ];
    my $labels = [ $self->labels ];
    my @values = map
      +{ id => $values->[$_], label => $labels->[$_] },
	0 .. $#$values;
    $field{select} =
      {
       id => "id",
       label => "label",
       values => \@values,
      };
  }

  return \%field;
}

=item name

The field name of the metadata.

=cut

sub validate {
  my ($self, %opts) = @_;

  my $value = delete $opts{value};
  defined $value
    or confess "value not supplied\n";
  my $rerror = delete $opts{error}
    or confess "error ref not supplied\n";
  my $section = $self->validation_section;

  # kind of clumsy
  require DevHelp::Validate;
  my @field_rules = $self->rules;
  $rule_map{$self->type} && unshift @field_rules, $rule_map{$self->type};
  my %values =
    (
     value => $value
    );
  my %fields =
    (
     value =>
     {
      rules => \@field_rules,
      description => $self->title,
     },
    );
  my %rules = %meta_rules;
  if ($self->type eq "enum") {
    $rules{meta_enum} =
      {
       match => "^(?:" . join("|", map quotemeta, $self->values) . ")\\z",
       error => '$n must be one of ' . join(", ", $self->values),
      };
  }

  my $val = DevHelp::Validate::Hash->new
    (
     fields => \%fields,
     rules => \%rules,
     cfg => $self->{cfg},
     section => $section,
    );
  my %errors;
  $val->validate(\%values, \%errors);
  if (keys %errors) {
    $$rerror = $errors{value};
    return;
  }

  return 1;
}

=item name

The field name of the metadata.

=cut

sub metanames {
  my ($self) = @_;

  if ($self->type eq 'image') {
    return ( $self->data_name, $self->width_name, $self->height_name );
  }
  else {
    return $self->name;
  }
}

=item data_name

The field name of the metadata.

=cut

sub data_name {
  $_[0]{data_name}
}

=item width_name

Where width information is stored for this image

=cut

sub width_name {
  $_[0]{width_name}
}

=item height_name

Where height information is stored for this image.

=cut

sub height_name {
  $_[0]{height_name}
}

=item display_name

Where the original filename is stored for the image.

=cut

sub display_name {
  $_[0]{display_name}
}

=head1 CLASS METHODS

=over

=item new

=cut

sub new {
  my $class = shift;
  my %opts = 
    (
     rules => '',
     ro => 0,
     values => [],
     cond => "1",
     type => "string",
     unit => '',
     help => '',
     width => 60,
     height => 40,
     @_
    );

  $opts{cfg} && $opts{cfg}->can("entry")
    or confess "Missing or invalid cfg parameter";
  $opts{name}
    or confess "Missing name parameter";
  $opts{name} =~ /^[A-Za-z_][A-Za-z0-9_-]*$/
    or confess "Invalid metadata name parameter";

  $field_defs{$opts{type}} 
    or confess "Unknown metadata type '$opts{type}' for field '$opts{name}'";

  my $name = $opts{name};
  for my $subkey (qw/data width height display/) {
    my $key = $subkey . "_name";
    defined $opts{$key} or $opts{$key} = $name . "_" . $subkey;
  }
  $opts{title} ||= $name;

  if ($opts{type} =~ /^(?:multi)?enum/) {
    if ($opts{values}) {
      unless (ref $opts{values}) {
	$opts{values} = [ split /;/, $opts{values} ];
      }
      @{$opts{values}}
	or confess "$opts{name} has enum type but no values";
    }
    else {
      confess "$opts{name} has enum type but no values";
    }

    if ($opts{labels}) {
      unless (ref $opts{labels}) {
	$opts{labels} = [ split /;/, $opts{labels} ];
      }
      @{$opts{labels}}
	or confess "$opts{name} has enum type but no labels";
    }
    else {
      $opts{labels} = $opts{values};
    }
  }

  $opts{htmltype} ||= $field_defs{$opts{type}}{htmltype};

  ref $opts{rules} or $opts{rules} = [ split /[,;]/, $opts{rules} ];

  if ($opts{cond}) {
    my $code = $opts{cond};
    $opts{cond} = eval 'sub { my $file = shift; my $obj = $file; ' . $code . ' }'
      or die "Cannot compile condition code <$code> for $opts{name}: $@";
  }
  else {
    $opts{cond} = sub { 1 };
  }

  bless \%opts, $class;
}

sub keys {
  qw/title help rules ro values labels type data_name width_name height_name cond unit htmltype width height/;
}

sub retrieve {
  my ($class, $req, $owner, $errors) = @_;

  my @meta;
  my @meta_delete;
  my $cgi = $req->cgi;
  my @metafields = grep !$_->ro, $owner->metafields($req->cfg);
  my %current_meta = map { $_ => 1 } $owner->metanames;
  for my $meta (@metafields) {
    my $name = $meta->name;
    my $cgi_name = "meta_$name";
    if ($cgi->param("delete_$cgi_name")) {
      for my $metaname ($meta->metanames) {
	push @meta_delete, $metaname
	  if $current_meta{$metaname};
      }
    }
    else {
      my $new;
      if ($meta->is_text) {
	my ($value) = $cgi->param($cgi_name);
	if (defined $value && 
	    ($value =~ /\S/ || $current_meta{$meta->name})) {
	  my $error;
	  if ($meta->validate(value => $value, error => \$error)) {
	    push @meta,
	      {
	       name => $name,
	       value => $value,
	      };
	  }
	  else {
	    $errors->{$cgi_name} = $error;
	  }
	}
      }
      else {
	my $im = $cgi->param($cgi_name);
	my $up = $cgi->upload($cgi_name);
	if (defined $im && $up) {
	  my $data = do { local $/; <$up> };
	  my ($width, $height, $type) = imgsize(\$data);

	  if ($width && $height) {
	    push @meta,
	      (
	       {
		name => $meta->data_name,
		value => $data,
		content_type => "image/\L$type",
	       },
	       {
		name => $meta->width_name,
		value => $width,
	       },
	       {
		name => $meta->height_name,
		value => $height,
	       },
	       {
		name => $meta->display_name,
		value => "" . $im,
	       },
	      );
	  }
	  else {
	    $errors->{$cgi_name} = $type;
	  }
	}
      }
    }
  }

  return { meta => \@meta, delete => \@meta_delete };
}

sub save {
  my ($class, $owner, $meta) = @_;

  for my $meta_delete (@{$meta->{meta}}, map $_->{name}, @{$meta->{delete}}) {
    $owner->delete_meta_by_name($meta_delete->{name});
  }
  for my $meta (@{$meta->{meta}}) {
    $owner->add_meta(%$meta, appdata => 1);
  }

  1;
}

sub all_metametadata {
  my ($class, $cfg) = @_;

  $cfg ||= BSE::Cfg->new;

  my @metafields;
  my @keys = $cfg->orderCS($class->fields_section);
  for my $name (@keys) {
    my %opts = ( name => $name );
    my $section = $class->name_section($name);
    for my $key ($class->keys) {
      my $value = $cfg->entry($section, $key);
      if (defined $value) {
	$opts{$key} = $value;
      }
    }
    push @metafields, $class->new(%opts, cfg => $cfg);
  }

  return @metafields;
}

1;

=back

=cut
