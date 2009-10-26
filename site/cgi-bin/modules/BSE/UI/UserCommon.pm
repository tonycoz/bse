package BSE::UI::UserCommon;
use strict;

# code common to both BSE::UserReg and BSE::UI::User
# see also BSE::UI::SiteuserCommon

my %num_file_fields = map { $_=> 1 }
  qw/id owner_id size_in_bytes/;

sub iter_userfiles {
  my ($self, $user, $req, $args) = @_;

  my @files = map $_->data_only, $user->visible_files($req->cfg);

  # produce a url for each file
  my $base = '/cgi-bin/user.pl?a_downufile=1&id=';
  for my $file (@files) {
    $file->{url} = $base . $file->{id};
  }
  defined $args or $args = '';

  my $sort;
  if ($args =~ s/\bsort:\s?(-?\w+(?:,-?\w+)*)\b//) {
    $sort = $1;
  }
  my $cgi_sort = $req->cgi->param('userfile_sort');
  $cgi_sort
    and $sort = $cgi_sort;
  if ($sort && @files > 1) {
    my @fields = map 
      {
	my $work = $_;
	my $rev = $work =~ s/^-//;
	[ $rev, $work ]
      } split /,/, $sort;

    @fields = grep exists $files[0]{$_->[1]}, @fields;

    @files = sort
      {
	for my $field (@fields) {
	  my $name = $field->[1];
	  my $diff = $num_file_fields{$name}
	    ? $a->{$name} <=> lc $b->{$name}
	      : $a->{$name} cmp lc $b->{$name};
	  if ($diff) {
	    return $field->[0] ? -$diff : $diff;
	  }
	}
	return 0;
      } @files;
  }

  $args =~ /\S/
    or return @files;

  if ($args =~ /^\s*filter:(.*)$/) {
    my $expr = $1;
    my $func = eval 'sub { my $file = $_[0];' .  $expr . '}';
    unless ($func) {
      print STDERR "** Cannot compile userfile filter $expr: $@\n";
      return;
    }
    return grep $func->($_), @files;
  }

  if ($args =~ /^\s*(!)?(\w+(?:,\w+)*)\s*$/) {
    my ($not, $cats) = ( $1, $2 );
    my %matches = map { $_ => 1 } split ',', $cats, -1;
    if ($not) {
      return grep !$matches{$_->{category}}, @files;
    }
    else {
      return grep $matches{$_->{category}}, @files;
    }
  }

  print STDERR "** unparsable arguments to userfile: $args\n";

  return;
}

1;
