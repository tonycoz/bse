package DevHelp::Tags::Iterate;
use strict;
use Carp qw(confess);

sub new {
  my ($class, %opts) = @_;

  return bless \%opts, $class;
}

sub escape {
  return $_[1];
}

sub _iter_reset_paged {
  my ($self, $rdata, $rindex) = @_;

  $$rindex = -1;

  1;
}

sub _iter_iterate {
  my ($self, $rdata, $rindex) = @_;

  return ++$$rindex < @$rdata;
}

sub _iter_item {
  my ($self, $rdata, $rindex, $single, $plural, $args) = @_;

  $$rindex >= 0 && $$rindex < @$rdata
    or return "** $single should only be used inside iterator $plural **";
  return $self->escape($rdata->[$$rindex]{$args});
}

sub _iter_number_paged {
  my ($self, $rindex, $baseindex) = @_;

  $$rindex + $baseindex + 1;
}

sub _iter_reset_page_counter {
  my ($self, $rpage) = @_;

  $$rpage = 1;
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
  my ($self, $rindex) = @_;

  $$rindex;
}

sub _iter_if_first {
  my ($self, $rindex) = @_;

  $$rindex == 0;
}

sub _iter_if_last {
  my ($self, $rdata, $rindex) = @_;

  $$rindex == $#$rdata;
}

sub make_paged_iterator {
  my ($self, $single, $plural, $rdata, $rindex, $cgi, $pagename,
      $perpage_parm, $save, $get) = @_;

  my ($def_per_page, $def_page_num);
  if ($get) {
    my ($code, @parms) = @$get;
    ($def_per_page, $def_page_num) = 
      $code->(@parms);
  }
  my $index;
  defined $rindex or $rindex = \$index;
  $$rindex = -1;
  $rdata or die;
  my $loaded = 0;
  my $max;
  my $perpage = ref $perpage_parm ? $$perpage_parm : $perpage_parm;
  unless ($perpage =~ /^\d+$/) {
    my ($name, $count) = $perpage =~ /^(\w+)=(\d+)$/
      or confess "Invalid perpage '$perpage'";
    $name ||= 'pp';
    $count ||= 10;
    my $work = $cgi->param($name);
    if (defined $work && $work =~ /^-?\d+$/ && 
	(($work >= 1 && $work <= 1000) || $work == -1)) {
      $perpage = $work;
    }
    else {
      $perpage = defined $def_per_page ? $def_per_page : $count;
    }
    $$perpage_parm =~ s/\d+/$perpage/ if ref $perpage_parm;
  }
  my $page_count = $perpage == -1 ? 1 : int((@$rdata + $perpage - 1) / $perpage);
  $page_count = 1 unless $page_count;
  $pagename ||= 'p';
  my $page_num = $cgi->param($pagename);
  defined $page_num or $page_num = $def_page_num;
  unless (defined($page_num) && $page_num =~ /^\d+$/
	  && $page_num >= 1 && $page_num <= $page_count) {
    $page_num = 1;
  }
  my ($base_index, $end_index);
  if ($perpage != -1) {
    $base_index = $perpage * ($page_num - 1);
    $end_index = $base_index + $perpage - 1;
    $end_index <= $#$rdata or $end_index = $#$rdata;
  }
  else {
    $base_index = 0;
    $end_index = $#$rdata;
  }
  my @data;
  @data = @$rdata[$base_index .. $end_index] if @$rdata;

  if ($save) {
    my ($code, @parms) = @$save;
    $code->(@parms, $perpage, $page_num);
  }

  my $page_counter;

  return
    (
     "iterate_${plural}_reset" => 
     [ _iter_reset_paged=>$self, \@data, $rindex ],
     "iterate_${plural}" =>
     [ _iter_iterate=>$self, \@data, $rindex, $single ],
     $single => [ _iter_item => $self, \@data, $rindex, $single, $plural ],
     "if\u$plural" => scalar(@data),
     "${single}_index" => [ _iter_index=>$self, $rindex ],
     "${single}_number" => [ _iter_number_paged=>$self, $rindex, $base_index ],
     "ifLast\u$single" => [ _iter_if_last=>$self, \@data, $rindex ],
     "ifFirst\u$single" => [ _iter_if_first=>$self, $rindex ],
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
     "${single}_totalcount" => scalar(@$rdata),
     "${plural}_firstnumber" => $base_index + 1,
     "${plural}_lastnumber" => $end_index + 1,
     "iterate_${single}_pages_reset" => 
     [ _iter_reset_page_counter=>$self, \$page_counter ],
     "iterate_${single}_pages" =>
     [ _iter_iterate_page_counter=>$self, \$page_counter, $page_count ],
     "${single}_pagecounter" =>
     [ _iter_page_counter=>$self, \$page_counter ],
     "${plural}_perpage" => $perpage,
    );
}

sub _iter_reset {
  my ($self, $rdata, $rindex, $code, $loaded, $nocache, 
      $args, $acts, $name, $templater) = @_;

  if (!$$loaded && !@$rdata && $code || $args || $nocache) {
    my ($sub, @args) = $code;

    if (ref $code eq 'ARRAY') {
      ($sub, @args) = @$code;
    }
    @$rdata = $sub->(@args, $args, $acts, $name, $templater);
    ++$$loaded unless $args;
  }

  $$rindex = -1;

  1;
}

sub _iter_number {
  my ($self, $rindex) = @_;

  1+$$rindex;
}

sub _iter_count {
  my ($self, $rdata, $code, $loaded, $nocache, 
      $args, $acts, $name, $templater) = @_;

  if (!$$loaded && !@$rdata && $code || $args || $nocache) {
    my ($sub, @args) = $code;

    if (ref $code eq 'ARRAY') {
      ($sub, @args) = @$code;
    }
    @$rdata = $sub->(@args, $args, $acts, $name, $templater);
    ++$$loaded unless $args;
  }

  scalar(@$rdata);
}

sub make_iterator {
  my ($self, $code, $single, $plural, $rdata, $rindex, $nocache) = @_;

  my $index;
  defined $rindex or $rindex = \$index;
  $$rindex = -1;
  $rdata ||= [];
  my $loaded = 0;
  return
    (
     "iterate_${plural}_reset" => 
     [ _iter_reset=>$self, $rdata, $rindex, $code, \$loaded, $nocache ],
     "iterate_${plural}" =>
     [ _iter_iterate=>$self, $rdata, $rindex, $nocache ],
     $single => 
     [ _iter_item=>$self, $rdata, $rindex, $single, $plural ],
     "${single}_index" => [ _iter_index=>$self, $rindex ],
     "${single}_number" => [ _iter_number =>$self, $rindex ],
     "if\u$plural" => 
     [ _iter_count=>$self, $rdata, $code, \$loaded, $nocache ],
     "${single}_count" => 
     [ _iter_count=>$self, $rdata, $code, \$loaded, $nocache ],
     "ifLast\u$single" => [ _iter_if_last=>$self, $rdata, $rindex ],
     "ifFirst\u$single" => [ _iter_if_first=>$self, $rindex ],
    );
}

1;
