package BSE::UI::AdminReorder;
use strict;
use base 'BSE::UI::AdminDispatch';
use BSE::TB::Articles;
use OtherParents;
use List::Util ();

our $VERSION = "1.002";

=head1 NAME

BSE::TB::AdminReorder - sort articles

=head1 SYNOPSIS

  /cgi-bin/reorder.pl?...

=head1 DESCRIPTION

Provides targets to sort child, allkids or stepparents.

Each target takes a sort specification in C<sort> and a reverse flag
in C<reverse>.

The sort spec can be any of:

=over

=item *

any one of the keywords C<title>, C<date>, C<current>, C<id> which
sort on title, last modification date, current sort order (as modified
by the reverse flag), or article id.  Default: C<current>.

=item *

the keyword C<shuffle> which randomizes the order.

=item *

a comma separated list of article field names, with optional reverse
flags.  eg. C<author,-title> to sort by author ascending, title
descending.

=back

If the reverse flag is true the sort order is reversed.

Each target accepts a C<refreshto> parameter, falling back to the C<r>
parameter to refresh to after sorting.  If neither is provided
refreshes to the admin menu.

=head1 TARGETS

=over

=cut

my %actions =
  (
   byparent => 1,
   bystepparent => 1,
   bystepchild => 1,
   error => 1,
  );

sub actions { \%actions }

sub rights { +{} }

sub default_action { "error" }

my %field_map =
  (
   parentid => 'byparent',
   stepparent => 'bystepparent',
   stepchild => 'bystepchild',
  );

sub other_action {
  my ($self, $cgi) = @_;

  for my $key (sort keys %field_map) {
    my ($value) = $cgi->param($key);
    if ($value) {
      return ( $field_map{$key}, $value );
    }
  }

  return;
}

=item byparent

Sort direct children of an article.

Selected if the C<parentid> parameter is present, which must be the id
of the parent article to sort the children by.

C<parentid> may be C<-1>.

Under Ajax, returns JSON like:

  {
    success: 1,
    kids: [ kidid, kidid ... ]
  }

Requires C<bse_edit_reorder_children> access on the given parent id.

=cut

sub req_byparent {
  my ($self, $req, $parentid) = @_;

  my $msg;
  $req->user_can(bse_edit_reorder_children => $parentid)
    or return $self->access_error($req, $msg);

  my ($kids, $order) = $self->_limit_and_order
    (
     $req,
     [
      map [ $_, $_, 'displayOrder' ], BSE::TB::Articles->getBy(parentid => $parentid)
     ]
    );

  if ($req->is_ajax) {
    return $req->json_content
      (
       success => 1,
       kids => [ map $_->id, @$kids ],
      );
  }

  $req->flash_notice("msg:bse/admin/reorder/byparent", [ $parentid, $order ]);

  my $cgi = $req->cgi;
  my $r = $cgi->param('refreshto') || $cgi->param('r')
    || $req->cfg->admin_url("menu");

  return $req->get_refresh($r);
}

=item bystepparent

Sort all kids of an article.

Selected if the C<stepparent> parameter is present, which must be the
id of the parent article to sort the children by.

C<stepparent> may B<not> be C<-1>.

Under Ajax, returns JSON like:

  {
    success: 1,
    kids: [ kidid, kidid ... ]
  }

Requires C<bse_edit_reorder_children> access on the given parent id.

=cut

sub req_bystepparent {
  my ($self, $req, $stepparent) = @_;

  my $msg;
  $req->user_can(bse_edit_reorder_children => $stepparent)
    or return $self->access_error($req, $msg);

  my $parent = BSE::TB::Articles->getByPkey($stepparent)
    or return $self->error($req, "Unknown article $stepparent");
  
  my @otherlinks = OtherParents->getBy(parentId => $stepparent);
  my @normalkids = BSE::TB::Articles->children($stepparent);
  my @stepkids = $parent->stepkids;
  my %stepkids = map { $_->{id}, $_ } @stepkids;
  my @kids =

  my ($kids, $order) = $self->_limit_and_order
    (
     $req,
     [
      map([ $_, $_, 'displayOrder' ], @normalkids),
      map([ $stepkids{$_->{childId}}, $_, 'parentDisplayOrder' ],
	  @otherlinks),
     ]
    );

  if ($req->is_ajax) {
    return $req->json_content
      (
       success => 1,
       kids => [ map $_->id, @$kids ],
      );
  }

  $req->flash_notice("msg:bse/admin/reorder/bystepparent", [ $stepparent, $order ]);

  my $cgi = $req->cgi;
  my $r = $cgi->param('refreshto') || $cgi->param('r')
    || $req->cfg->admin_url("menu");

  return $req->get_refresh($r);
}

=item bystepchild

Sort step parents of an article.

Selected if the C<stepchild> parameter is true, which must be the id
of the child article to sort the step parents of.

C<stepchild> may B<not> be C<-1>.

Under Ajax, returns JSON like:

  {
    success: 1,
    parents: [ parentid, parentid ... ]
  }

Requires C<bse_edit_reorder_children> access on the given step child id.

=cut

sub req_bystepchild {
  my ($self, $req, $stepchild) = @_;

  my $msg;
  $req->user_can(bse_edit_reorder_children => $stepchild)
    or return $self->access_error($req, $msg);

  my $child = BSE::TB::Articles->getByPkey($stepchild)
    or return $self->error($req, "Unknown child $stepchild");

  my @otherlinks = OtherParents->getBy(childId=>$stepchild);
  my @stepparents = map BSE::TB::Articles->getByPkey($_->{parentId}), @otherlinks;
  my %stepparents = map { $_->{id}, $_ } @stepparents;


  my ($parents, $order) = $self->_limit_and_order
    (
     $req,
     [
      map([ $stepparents{$_->{parentId}}, $_, 'childDisplayOrder' ],
	  @otherlinks),
     ]
    );

  if ($req->is_ajax) {
    return $req->json_content
      (
       success => 1,
       parents => [ map $_->id, @$parents ],
      );
  }

  $req->flash_notice("msg:bse/admin/reorder/bystepchild", [ $stepchild, $order ]);

  my $cgi = $req->cgi;
  my $r = $cgi->param('refreshto') || $cgi->param('r')
    || $req->cfg->admin_url("menu");

  return $req->get_refresh($r);
}

sub _sort {
  my ($self, $sort, $cgi, $kids) = @_;

  my $reverse = $cgi->param('reverse');
  
  my $code;
  my $order = $sort;
  if ($sort eq 'title') {
    $code = sub { lc($a->[0]{title}) cmp lc($b->[0]{title}) };
  }
  elsif ($sort eq 'date') {
    $code = sub { $a->[0]{lastModified} cmp $b->[0]{lastModified} };
  }
  elsif ($sort eq 'current') {
    $code = sub { $b->[1]{$b->[2]} <=> $a->[1]{$a->[2]} };
    $order = '';
  }
  elsif ($sort eq 'id') {
    $code = sub { $a->[0]{id} <=> $b->[0]{id} };
  }
  elsif (@$kids) {
    my @fields = split ',', $sort;
    my @reverse = grep(s/^-// || 0, @fields);
    my %reverse;
    @reverse{@fields} = @reverse;
    @fields = grep exists($kids->[0][0]{$_}), @fields;
    my @num = 
    my %num = map { $_ => 1 } BSE::TB::Article->numeric;

    $code =
      sub {
	for my $field (@fields) {
	  my $rev = $reverse{$field};
	  my $cmp;
	  if ($num{$field}) {
	    $cmp = $a->[0]{$field} <=> $b->[0]{$field};
	  }
	  else {
	    $cmp = lc $a->[0]{$field} cmp lc $b->[0]{$field};
	  }
	  $cmp = -$cmp if $rev;
	  return $cmp if $cmp;
	}
	return $a->[0]{id} <=> $b->[0]{id};
      };
  }
  if ($reverse) {
    my $temp = $code;
    $code = sub { -$temp->() };
    $order .= $order ? ", reversed" : "reverse";
  }

  $kids = [ sort $code @$kids ];

  return ( $kids, $order );
}

sub _shuffle {
  my ($self, $kids) = @_;

  $kids = [ List::Util::shuffle(@$kids) ];

  return ( $kids, "shuffle" );
}

sub _limit_and_order {
  my ($self, $req, $kids) = @_;

  my $cgi = $req->cgi;
  my $type = $cgi->param("type");
  if ($type) {
    $kids = [ grep $_->[0]{generator} =~ /::\Q$type\E$/, @$kids ];
  }

  my @order = sort { $b <=> $a } map $_->[1]{$_->[2]}, @$kids;
  my $sort = join(",", $cgi->param('sort')) || 'current';
  $sort =~ s/-,/-/g;

  my $order;
  if ($sort eq 'shuffle') {
    ($kids, $order) = $self->_shuffle($kids);
  }
  else {
    ($kids, $order) = $self->_sort($sort, $cgi, $kids);
  }

  for my $i (0..$#$kids) {
    my $kid = $kids->[$i];
    $kid->[1]{$kid->[2]} = $order[$i];
    $kid->[1]->save();
  }

  return [ map $_->[0], @$kids ], $order;
}

sub req_error {
  my ($self, $req) = @_;

  if ($req->is_ajax) {
    return 
      {
       headers => [ "Status: 404" ]
      };
  }

  return $self->error($req, "Can't figure out what you want to do");
}

1;

=back

=head1 AUTHOR

Tony Cook <tony@develop-help.com>

=cut
