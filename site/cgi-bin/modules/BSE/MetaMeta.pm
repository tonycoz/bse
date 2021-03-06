package BSE::MetaMeta;
use strict;
use Carp qw(confess);
use Image::Size;
use Fcntl ':seek';

our $VERSION = "1.005";

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
    type => "image",
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

=item fieldtype

How to parse this field.  May be ignored depending on type.

=cut

sub fieldtype { $_[0]{fieldtype} }

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
     description => scalar $self->title,
     units => scalar $self->unit,
     rules => [ $self->rules ],
     rawtype => scalar $self->type,
     htmltype => scalar $self->htmltype,
     type => scalar $self->fieldtype,
     width => scalar $self->width,
     height => scalar $self->height,
    );
  my $defs = $field_defs{$self->type};
  for my $key (keys %$defs) {
    defined $field{$key} or $field{$key} = $defs->{$key};
  }
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
  my %fields = ( $self->name => \%field );

  require BSE::Validate;
  my $configured = 
    BSE::Validate::bse_configure_fields({ $self->name => \%fields }, BSE::Cfg->single,
					$self->validation_section);

  return $fields{$self->name};
}

=item validate

Validate a meta data item.

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

=item metanames

List of form fields that are read for the meta item.

=cut

sub metanames {
  my ($self) = @_;

  if ($self->type eq 'image') {
    return ( $self->data_name, $self->width_name, $self->height_name, $self->display_name );
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

=back

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
     fieldtype => "",
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
  unshift @{$opts{rules}}, $rule_map{$opts{type}};

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
  qw/title help rules ro values labels type data_name width_name height_name cond unit htmltype width height fieldtype/;
}

sub retrieve {
  my ($class, $req, $owner, $errors, %opts) = @_;

  my $api = $opts{api};
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
      my %fields =
	(
	 $cgi_name => $meta->field,
	);
      if ($req->validate(fields => \%fields,
			 rules => \%meta_rules,
			 errors => $errors)) {
	my $values = $req->cgi_fields
	  (
	   fields => \%fields,
	   api => $api,
	  );
	my $value = $values->{$cgi_name};
	if ($meta->is_text) {
	  if (defined $value && 
	      ($value =~ /\S/ || $current_meta{$meta->name})) {
	    utf8::encode($value);
	    push @meta,
	      {
	       name => $name,
	       value => $value,
	      };
	  }
	}
	else {
	  if ($value) {
	    my $up = $value->{fh};
	    binmode $up;
	    seek $up, 0, SEEK_SET;
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
		  value => "" . $value->{filename},
		 },
		);
	    }
	  }
	}
      }
    }
  }

  return { meta => \@meta, delete => \@meta_delete };
}

sub save {
  my ($class, $owner, $meta) = @_;

  for my $meta_delete (@{$meta->{delete}}, map $_->{name}, @{$meta->{meta}}) {
    $owner->delete_meta_by_name($meta_delete);
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
