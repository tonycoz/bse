package BSE::TB::Orders;
use strict;
use Squirrel::Table;
use vars qw(@ISA $VERSION);
@ISA = qw(Squirrel::Table);
use BSE::TB::Order;

our $VERSION = "1.004";

sub rowClass {
  return 'BSE::TB::Order';
}

# shipping methods when we don't automate shipping
sub dummy_shipping_methods {
  my $cfg = BSE::Cfg->single;

  my %ship = $cfg->entriesCS("dummy shipping methods");
  my @ship;
  for my $key (sort { $ship{$a} cmp $ship{$b} } keys %ship) {
    my $name = $key;
    $ship{$key} =~ /,(.*)/ and $name = $1;

    push @ship, { id => $key, name => $name };
  }

  unshift @ship,
    {
     id => "",
     name => "(None selected)",
    };

  return @ship;
}

=item stages()

Return the possible values for the order stage field.

=cut

sub stages {
  return qw(incomplete unprocessed backorder picked shipped cancelled stalled returned);
}

=item settable_stages()

Return the stages that the admin can set the order stage to.

=cut

sub settable_stages {
  my ($class) = @_;

  return grep $_ ne "incomplete", $class->stages;
}

=item stage_labels($lang)

Return descriptive labels for the stage values.

=cut

sub stage_labels {
  my ($self, $lang) = @_;

  return map { $_ => $self->stage_label($_, $lang) } $self->stages;
}

=item stage_label($stage, $lang)

Given a stage value, return the label.

=cut

sub stage_label {
  my ($self, $stage, $lang) = @_;

  require BSE::Message;
  my $msgs = BSE::Message->new;

  return $msgs->text($lang, $self->stage_label_id($stage), [], $stage);
}

sub stage_label_id {
  my ($self, $stage) = @_;

  return "msg:bse/shop/orderstages/$stage";
}

1;
