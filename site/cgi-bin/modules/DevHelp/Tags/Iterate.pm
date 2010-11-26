package DevHelp::Tags::Iterate;
use strict;
use Carp qw(confess);

our $VERSION = "1.003";

sub new {
  my ($class, %opts) = @_;

  return bless \%opts, $class;
}

sub escape {
  return $_[1];
}

sub next_item {
  my ($self, $item, $single, $state) = @_;

  if ($state->{changed}) {
    $state->{changed}->($item);
  }
}

sub _iter_reset_paged {
  my ($self, $state) = @_;

  ${$state->{index}} = -1;

  $self->next_item(undef, $state->{single}, $state);
  $state->{previous} = undef;
  $state->{item} = undef;
  if (@{$state->{data}}) {
    $state->{next} = $self->_load($state, $state->{data}[0]);
  }
  else {
    $state->{next} = undef;
  }

  undef ${$state->{store}} if $state->{store};

  1;
}

sub _load {
  my ($self, $state, $item) = @_;

  $state->{fetch} or return $item;

  my $fetch = $state->{fetch};
  my $code = $fetch;
  my @args;
  if (ref $fetch eq 'ARRAY') {
    ($code, @args) = @$fetch;
  }
  if ($state->{state}) {
    push @args, $state->{state};
  }
  push @args, $item;
  if (ref $code) {
    ($item) = $code->(@args);
  }
  else {
    my $object = shift @args;
    ($item) = $object->$code(@args);
  }

  return $item;
}

sub _iter_iterate {
  my ($self, $state) = @_;

  if (++${$state->{index}} < @{$state->{data}}) {
    $state->{previous} = $state->{item};
    $state->{item} = $state->{next};
    if (${$state->{index}} < $#{$state->{data}}) {
      $state->{next} = $self->_load($state, $state->{data}[${$state->{index}}+1]);
    }
    else {
      $state->{next} = undef;
    }
    ${$state->{store}} = $state->{item} if $state->{store};
    $self->next_item($state->{item}, $state->{single}, $state);
    return 1;
  }
  else {
    $state->{item} = undef;
    ${$state->{store}} = undef if $state->{store};
    $self->next_item(undef, $state->{single}, $state);
  }
  return;
}

sub item {
  my ($self, $entry, $args) = @_;

  my $value = $entry->{$args};
  defined $value or return '';

  return $self->escape($value);
}

sub _iter_item {
  my ($self, $state, $args) = @_;

  $state->{item}
    or return "** $state->{single} should only be used inside iterator $state->{plural} **";

  return $self->item($state->{item}, $args);
}

sub _iter_number_paged {
  my ($self, $state) = @_;

  ${$state->{index}} + $state->{base_index} + 1;
}

sub _iter_reset_page_counter {
  my ($self, $rpage) = @_;

  $$rpage = 0;
}

sub _iter_iterate_page_counter {
  my ($self, $rpage, $page_count) = @_;

  ++$$rpage <= $page_count;
}

sub _iter_page_counter {
  my ($self, $rpage) = @_;

  $$rpage;
}

sub _iter_index {
  my ($self, $state) = @_;

  ${$state->{index}};
}

sub _iter_if_first {
  my ($self, $state) = @_;

  ${$state->{index}} == 0;
}

sub _iter_if_last {
  my ($self, $state) = @_;

  ${$state->{index}} == $#{$state->{data}};
}

sub _iter_previous {
  my ($self, $state, $args) = @_;

  $state->{previous} or return '';

  return $self->item($state->{previous}, $args);
}

sub _iter_next {
  my ($self, $state, $args) = @_;

  $state->{next} or return '';

  return $self->item($state->{next}, $args);
}

sub _iter_if_previous {
  my ($self, $state) = @_;

  return defined $state->{previous};
}

sub _iter_if_next {
  my ($self, $state) = @_;

  return defined $state->{next};
}

sub _get_values {
  my ($state, $args, $acts, $name, $templater) = @_;

  my $code = $state->{code};
  my @args;
  if (ref $code eq 'ARRAY') {
    ($code, @args) = @$code;
  }
  if ($state->{state}) {
    push @args, $state;
  }
  
  if (ref $code) {
    return $code->(@args, $args, $acts, $name, $templater);
  }
  else {
    my $object = shift @args;
    return $object->$code(@args, $args, $acts, $name, $templater);
  }
}

sub make_paged_iterator {
  my ($self, $single, $plural, $rdata, $rindex, $cgi, $pagename,
      $perpage_parm, $save, $get, $rstore) = @_;

  return $self->make_paged(single => $single,
			   plural => $plural, 
			   data => $rdata,
			   index => $rindex,
			   cgi => $cgi,
			   pagename => $pagename,
			   perpage_parm => $perpage_parm,
			   save => $save,
			   get => $get,
			   store => $rstore);
}

sub page_iterator_obj {
  return DevHelp::Tags::Iterate->new;
}

sub page_iterator_size {
  return 20;
}

sub iter_pages {
  my ($self, $page_count, $page_num) = @_;

  my $size = $self->page_iterator_size;
  if ($page_count <= $size+2) {
    return map +{ page => $_, link => $_ != $page_num, gap => 0 }, 1 .. $page_count;
  }
  my @entries;
  my $counter = 1;
  if ($page_num <= $size / 2) {
    my $first_limit = int($size * 0.66)+1;
    push @entries, map +{ page => $_, link => $_ != $page_num, gap => 0 }, 1 .. $first_limit;
    push @entries, { page => '...', link => 0, gap => 1 };
    my $last_limit = $page_count - ($size - @entries) + 1;
    push @entries, map +{ page => $_, link => $_ != $page_num, gap => 0 }, $last_limit .. $page_count;
  }
  elsif ($page_num >= int($page_count - $size / 2)) {
    my $last_limit = $page_count - int($size * 0.66);
    my $first_limit = $page_count - $last_limit - 2;
    push @entries, map +{ page => $_, link => $_ != $page_num, gap => 0 }, 1 .. $first_limit;
    push @entries, { page => "...", link => 0, gap => 1 };
    push @entries, map +{ page => $_, link => $_ != $page_num, gap => 0 }, $last_limit .. $page_count;
  }
  else {
    my $middle_count = int($size / 3) + 1;
    ($middle_count & 1) == 0 and ++$middle_count;
    my $mid_diff = ($middle_count-1) / 2;
    my $side_count = int($size - $middle_count - 2) / 2;
    push @entries, map +{ page => $_, link => 1, gap => 0 }, 1 .. $side_count;
    push @entries, { page => "...", link => 0, gap => 1 };
    my $mid_first = $page_num - $mid_diff;
    my $mid_last = $page_num + $mid_diff;
    push @entries, map +{ page => $_, link => $_ != $page_num, gap => 0 }, $mid_first .. $mid_last;
    push @entries, { page => "...", link => 0, gap => 1 };
    my $last_limit = $page_count - $side_count + 1;
    push @entries, map +{ page => $_, link => 1, gap => 0 }, $last_limit .. $page_count;
  }

  return @entries;
}

sub make_paged {
  my ($self, %state) = @_;

  my ($def_per_page, $def_page_num);
  if ($state{get}) {
    my ($code, @parms) = @{$state{get}};
    ($def_per_page, $def_page_num) = 
      $code->(@parms);
  }
  my $index;
  $state{index} ||= \$index;
  ${$state{index}} = -1;
  $state{data} or die;
  $state{loaded} = 0;
  my $max;
  my $perpage = ref $state{perpage_parm} ? ${$state{perpage_parm}} : $state{perpage_parm};
  unless ($perpage =~ /^\d+$/) {
    my ($name, $count) = $perpage =~ /^(\w+)=(\d+)$/
      or confess "Invalid perpage '$perpage'";
    $name ||= 'pp';
    $count ||= 10;
    my $work = $state{cgi}->param($name);
    if (defined $work && $work =~ /^-?\d+$/ && 
	(($work >= 1 && $work <= 1000) || $work == -1)) {
      $perpage = $work;
    }
    else {
      $perpage = defined $def_per_page ? $def_per_page : $count;
    }
    ${$state{perpage_parm}} =~ s/\d+/$perpage/ if ref $state{perpage_parm};
  }
  my $page_count = $perpage == -1 ? 1 : 
    int(( @{$state{data}} + $perpage - 1 ) / $perpage);
  $page_count = 1 unless $page_count;
  $state{pagename} ||= 'p';
  my $page_num = $state{cgi}->param($state{pagename});
  defined $page_num or $page_num = $def_page_num;
  unless (defined($page_num) && $page_num =~ /^\d+$/
	  && $page_num >= 1 && $page_num <= $page_count) {
    $page_num = 1;
  }
  my ($base_index, $end_index);
  if ($perpage != -1) {
    $base_index = $perpage * ($page_num - 1);
    $end_index = $base_index + $perpage - 1;
    $end_index <= $#{$state{data}} or $end_index = $#{$state{data}};
  }
  else {
    $base_index = 0;
    $end_index = $#{$state{data}};
  }
  $state{base_index} = $base_index;
  my $total_count = @{$state{data}};
  my @data;
  @data = @{$state{data}}[$base_index .. $end_index];
  $state{data} = \@data;

  if ($state{save}) {
    my ($code, @parms) = @{$state{save}};
    $code->(@parms, $perpage, $page_num);
  }

  my $page_counter;

  my $it = $self->page_iterator_obj;

  my $plural = $state{plural};
  my $single = $state{single};
  return
    (
     "iterate_${plural}_reset" => [ _iter_reset_paged=>$self, \%state ],
     "iterate_${plural}" => [ _iter_iterate=>$self, \%state ],
     $single => [ _iter_item => $self, \%state ],
     "if\u$plural" => scalar(@data),
     "${single}_index" => [ _iter_index=>$self, \%state ],
     "${single}_number" => [ _iter_number_paged=>$self, \%state ],
     "ifLast\u$single" => [ _iter_if_last=>$self, \%state ],
     "ifFirst\u$single" => [ _iter_if_first=>$self, \%state ],
     "ifNext\u${plural}\EPage" => $page_num < $page_count,
     "ifPrev\u${plural}\EPage" => $page_num > 1,
     "ifFirst\u${plural}\EPage" => $page_num == 1,
     "ifLast\u${plural}\EPage" => $page_num == $page_count,
     "next\u${plural}\EPage" => 
     ( $page_num < $page_count ? $page_num + 1 : $page_num ),
     "prev\u${plural}\EPage" =>
     ( $page_num > 1 ? $page_num - 1 : 1 ),
     "${single}_count" => scalar(@data),
     "${plural}_pagenum" => $page_num,
     "${plural}_pagecount" => $page_count,
     "${single}_totalcount" => $total_count,
     "${plural}_firstnumber" => $base_index + 1,
     "${plural}_lastnumber" => $end_index + 1,
     "iterate_${single}_pages_reset" =>
     [ _iter_reset_page_counter=>$self, \$page_counter ],
     "iterate_${single}_pages" =>
     [ _iter_iterate_page_counter=>$self, \$page_counter, $page_count ],
     "${single}_pagecounter" =>
     [ _iter_page_counter=>$self, \$page_counter ],
     "${plural}_perpage" => $perpage,
     "previous_${single}"       => [ _iter_previous=>$self, \%state ],
     "next_${single}"           => [ _iter_next=>$self, \%state ],
     $it->make
     (
      single => "${single}_pagec",
      plural => "${plural}_pagec",
      code => [ iter_pages => $self, $page_count, $page_num ],
     ),
#      "${plural}_pagelist" =>
#      [ _iter_pagelist => $self, $page_num, $page_count, $pagename ],
#      "${plural}_firstpage" =>
#      [ _iter_firstpage => $self, $page_num, $page_count, $pagename ],
#      "${plural}_backonepage" =>
#      [ _iter_backonepage => $self, $page_num, $page_count, $pagename ],
    );
}

sub _iter_reset {
  my ($self, $state, $args, $acts, $name, $templater) = @_;

  if (!$state->{loaded} && !@{$state->{data}} && $state->{code} || $args || $state->{nocache}) {
    @{$state->{data}} = _get_values($state, $args, $acts, $name, $templater);
    ++$state->{loaded} unless $args;
  }

  ${$state->{index}} = -1;
  $self->next_item(undef, $state->{single}, $state);
  $state->{previous} = undef;
  $state->{item} = undef;
  if (@{$state->{data}}) {
    $state->{next} = $self->_load($state, $state->{data}[0]);
  }
  else {
    $state->{next} = undef;
  }

  undef ${$state->{store}} if $state->{store};

  1;
}

sub _iter_number {
  my ($self, $state) = @_;

  1+${$state->{index}};
}

sub _iter_count {
  my ($self, $state, $args, $acts, $name, $templater) = @_;

  if (!$state->{loaded} && !@{$state->{data}} && $state->{code} || $args || $state->{nocache}) {
    @{$state->{data}} = _get_values($state, $args, $acts, $name, $templater);
    ++$state->{loaded} unless $args;
  }

  scalar(@{$state->{data}});
}

sub make_iterator {
  my ($self, $code, $single, $plural, $rdata, $rindex, $nocache, $rstore) = @_;

  return $self->make(code => $code,
		     single => $single,
		     plural => $plural,
		     data => $rdata,
		     index => $rindex,
		     nocache => $nocache,
		     store => $rstore);
}

=item standard iterator

=cut

sub make {
  my ($self, %opts) = @_;

  $opts{single} or confess "Missing 'single' parameter";
  $opts{plural} or confess "Missing 'plural' parameter";

  my $index;
  $opts{index} ||= \$index;
  $opts{data} ||= [];
  $opts{loaded} = 0;
  ${$opts{'index'}} = -1;
  my $plural = $opts{plural};
  my $single = $opts{single};
  return
    (
     "iterate_${plural}_reset"	=> [ _iter_reset=>$self, \%opts ],
     "iterate_${plural}"	=> [ _iter_iterate=>$self, \%opts ],
     $single			=> [ _iter_item=>$self, \%opts ],
     "${single}_index"		=> [ _iter_index=>$self, \%opts ],
     "${single}_number"		=> [ _iter_number =>$self, \%opts ],
     "if\u$plural"		=> [ _iter_count=>$self, \%opts ],
     "${single}_count"		=> [ _iter_count=>$self, \%opts ],
     "ifLast\u$single"		=> [ _iter_if_last=>$self, \%opts ],
     "ifFirst\u$single"		=> [ _iter_if_first=>$self, \%opts ],
     "previous_${single}"       => [ _iter_previous=>$self, \%opts ],
     "next_${single}"           => [ _iter_next=>$self, \%opts ],
     "ifPrevious\u$single"      => [ _iter_if_previous=>$self, \%opts ],
     "ifNext\u$single"          => [ _iter_if_next=>$self, \%opts ],
     $self->more_tags(\%opts),
    );
}

sub more_tags {
  return;
}

1;
