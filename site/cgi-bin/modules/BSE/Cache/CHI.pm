package BSE::Cache::CHI;
use strict;
use CHI;

our $VERSION = "1.002";

sub new {
  my ($class, $cfg) = @_;

  my %opts;

  my $params_str = $cfg->entry("cache", "chi_params");
  my @eval_res = eval $params_str;
  if ($@) {
    print STDERR "Error evaluating cache parameters: $@\n";
    return;
  }
  my $cache = CHI->new(@eval_res);

  my $self = bless { cache => $cache }, $class;
}

sub set {
  my ($self, $key, $value) = @_;

  $self->{cache}->set($key, $value);
}

sub get {
  my ($self, $key) = @_;

  my $value = $self->{cache}->get($key);
  defined $value or return;

  return $value;
}

sub delete {
  my ($self, $key) = @_;

  $self->{cache}->remove($key);
}

1;

