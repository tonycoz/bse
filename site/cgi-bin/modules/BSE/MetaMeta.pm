package BSE::MetaMeta;
use strict;
use Carp qw(confess);
use Image::Size;

our $VERSION = "1.001";

my %meta_rules =
  (
   meta_real =>
   {
    match => qr/^\s*[+-]?(?:\d+(?:\.\d+)|\.\d+)(?:[eE][+-]?\d+)?\s*\z/,
    error => '$n must be a number',
   },
  );

my %rule_map =
  (
   integer => "integer",
   string => "dh_one_line",
   real => "meta_real",
   enum => "meta_enum", # generated
  );

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
     @_
    );

  $opts{cfg} && $opts{cfg}->can("entry")
    or confess "Missing or invalid cfg parameter";
  $opts{name}
    or confess "Missing name parameter";
  $opts{name} =~ /^[a-z]\w*$/i
    or confess "Invalid metadata name parameter";

  my $name = $opts{name};
  for my $subkey (qw/data width height/) {
    my $key = $subkey . "_name";
    defined $opts{$key} or $opts{$key} = $name . "_" . $subkey;
  }
  $opts{title} ||= $name;

  if ($opts{type} eq "enum") {
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

  ref $opts{rules} or $opts{rules} = [ split /[,;]/, $opts{rules} ];

  if ($opts{cond}) {
    my $code = $opts{cond};
    $opts{cond} = eval 'sub { my $file = shift; ' . $code . ' }'
      or die "Cannot compile condition code <$code> for $opts{name}: $@";
  }
  else {
    $opts{cond} = sub { 1 };
  }

  bless \%opts, $class;
}

sub name { $_[0]{name} }

sub type { $_[0]{type} }

sub title { $_[0]{title} }

sub rules { @{$_[0]{rules}} }

sub values { @{$_[0]{values}} }

sub labels { @{$_[0]{labels}} }

sub ro { $_[0]{ro} }

sub unit { $_[0]{unit} }

sub is_text {
  $_[0]{type} ne "image";
}

sub cond {
  my ($self, $file) = @_;

  return $self->{cond}->($file);
}

sub validate {
  my ($self, %opts) = @_;

  my $value = delete $opts{value};
  defined $value
    or confess "value not supplied\n";
  my $rerror = delete $opts{error}
    or confess "error ref not supplied\n";

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
     section => $self->validation_section,
    );
  my %errors;
  $val->validate(\%values, \%errors);
  if (keys %errors) {
    $$rerror = $errors{value};
    return;
  }

  return 1;
}

sub metanames {
  my ($self) = @_;

  if ($self->type eq 'image') {
    return ( $self->data_name, $self->width_name, $self->height_name );
  }
  else {
    return $self->name;
  }
}

sub data_name {
  $_[0]{data_name}
}

sub width_name {
  $_[0]{width_name}
}

sub height_name {
  $_[0]{height_name}
}

sub keys {
  qw/title help rules ro values labels type data_name width_name height_name cond unit/;
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

1;
