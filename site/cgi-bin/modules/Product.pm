package Product;
use strict;
# represents a product from the database
use Articles;
use vars qw/@ISA/;
@ISA = qw/Article/;

our $VERSION = "1.000";

# subscription_usage values
use constant SUBUSAGE_START_ONLY => 1;
use constant SUBUSAGE_RENEW_ONLY => 2;
use constant SUBUSAGE_EITHER => 3;

sub columns {
  return ($_[0]->SUPER::columns(), 
	  qw/articleId description leadTime retailPrice wholesalePrice gst options
             subscription_id subscription_period subscription_usage
             subscription_required product_code weight length height width/ );
}

sub bases {
  return { articleId=>{ class=>'Article'} };
}

sub subscription_required {
  my ($self) = @_;

  my $id = $self->{subscription_required};
  return if $id == -1;

  require BSE::TB::Subscriptions;
  return BSE::TB::Subscriptions->getByPkey($id);
}

sub subscription {
  my ($self) = @_;

  my $id = $self->{subscription_id};
  return if $id == -1;

  require BSE::TB::Subscriptions;
  return BSE::TB::Subscriptions->getByPkey($id);
}

sub is_renew_sub_only {
  my ($self) = @_;

  $self->{subscription_usage} == SUBUSAGE_RENEW_ONLY;
}

sub is_start_sub_only {
  my ($self) = @_;

  $self->{subscription_usage} == SUBUSAGE_START_ONLY;
}

sub _get_cfg_options {
  my ($cfg) = @_;

  require BSE::CfgInfo;
  my $avail_options = BSE::CfgInfo::product_options($cfg);
  my @options;
  for my $name (keys %$avail_options) {
    my $rawopt = $avail_options->{$name};
    my %opt =
      (
       id => $name,
       name => $rawopt->{desc},
       default => $rawopt->{default} || '',
      );
    my @values;
    for my $value (@{$rawopt->{values}}) {
      my $label = $rawopt->{labels}{$value} || $value;
      push @values,
	bless
	  {
	   id => $value,
	   value => $label,
	  }, "BSE::CfgProductOptionValue";
    }
    $opt{values} = \@values;
    push @options, bless \%opt, "BSE::CfgProductOption";
  }

  return @options;
}

sub _get_prod_options {
  my ($product, $cfg, @values) = @_;

  my %all_cfg_opts = map { $_->id => $_ } _get_cfg_options($cfg);
  my @opt_names = split /,/, $product->{options};

  my @cfg_opts = map $all_cfg_opts{$_}, @opt_names;
  my @db_opts = grep $_->enabled, $product->db_options;
  my @all_options = ( @cfg_opts, @db_opts );

  push @values, '' while @values < @all_options;

  my $index = 0;
  my @sem_options;
  for my $opt (@all_options) {
    my @opt_values = $opt->values;
    my %opt_values = map { $_->id => $_->value } @opt_values;
    my $result_opt = 
      {
       id => $opt->key,
       name => $opt->key,
       desc => $opt->name,
       value => $values[$index],
       type => $opt->type,
       labels => \%opt_values,
       default => $opt->default_value,
      };
    my $value = $values[$index];
    if (defined $value) {
      $result_opt->{values} = [ map $_->id, @opt_values ],
      $result_opt->{display} = $opt_values{$values[$index]};
    }
    push @sem_options, $result_opt;
    ++$index;
  }

  return @sem_options;
}

sub option_descs {
  my ($self, $cfg, $rvalues) = @_;

  $rvalues or $rvalues = [ ];

  return $self->_get_prod_options($cfg, @$rvalues);
}

sub db_options {
  my ($self) = @_;

  require BSE::TB::ProductOptions;
  return BSE::TB::ProductOptions->getBy(product_id => $self->{id});
}

sub remove {
  my ($self, $cfg) = @_;

  # remove any product options
  for my $opt ($self->db_options) {
    $opt->remove;
  }

  # mark any order line items to "anonymize" them
  BSE::DB->run(bseMarkProductOrderItemsAnon => $self->id);

  # remove any wishlist items
  BSE::DB->run(bseRemoveProductFromWishlists => $self->id);

  return $self->SUPER::remove($cfg);
}

sub has_sale_files {
  my ($self) = @_;

  my ($row) = BSE::DB->query(bseProductHasSaleFiles => $self->{id});

  return $row->{have_sale_files};
}

package BSE::CfgProductOption;
use strict;

sub id { $_[0]{id} }

sub key {$_[0]{id} } # same as id for config options

sub type { "select" }

sub name { $_[0]{name} }

sub values {
  @{$_[0]{values}}
}

sub default_value { $_[0]{default} }

package BSE::CfgProductOptionValue;
use strict;

sub id { $_[0]{id} }

sub value { $_[0]{value} }

1;
