#!/usr/bin/perl -w
# -d:ptkdb
BEGIN { $ENV{DISPLAY} = '192.168.32.15:0.0' }
use strict;
use FindBin;
use lib "$FindBin::Bin/../modules";
use Articles;
use Article;
use BSE::DB;
use BSE::Request;
use BSE::Template;
use BSE::Edit::Base;
use Carp qw'verbose';
use Carp 'confess';

#  $SIG{__DIE__} = 
#    sub { 
#      if ($@ =~ /^ENOIMPL\b/) {
#        die $@;
#      }
#      else {
#        confess $@;
#      }
#    };

my $req = BSE::Request->new;
my $cgi = $req->cgi;
my $cfg = $req->cfg;
my $id = $cgi->param('id');
my $articles = 'Articles'; # for a later switch to proper objects, I hope
my $result;
if (defined $id && $id =~ /\d/ && $id == -1) {
  my $obj = get_class('BSE::Edit::Site', $cfg)
    or die "Cannot get sections class";
  $result = $obj->edit_sections($req, $articles);
}
elsif (my ($obj, $article) = BSE::Edit::Base->article_class_id($id, $articles, $cfg)) {
  $result = $obj->article_dispatch($req, $article, $articles);
}
else {
  # look for a type
  my $obj;
  my $type = $cgi->param('type');
  if ($type && $type !~ /\W/) {
    my $class = "BSE::Edit::$type";
    $obj = get_class($class, $cfg);
  }
  unless ($obj) {
    my $parentid = $cgi->param('parentid');
    my $parent;
    if (($obj, $parent) = BSE::Edit::Base->article_class_id($parentid, $articles, $cfg)) {
      if (my ($class) = $obj->child_types($parent)) {
	$obj = get_class($class, $cfg);
      }
      else {
	undef $obj;
      }
    }
  }
  unless ($obj) {
    # last try
    $obj = get_class("BSE::Edit::Article", $cfg)
      or die "Cannot get article class!!";
  }
  $result = $obj->noarticle_dispatch($req, $articles);
}

$| = 1;
push @{$result->{headers}}, "Content-Type: $result->{type}";
push @{$result->{headers}}, $req->extra_headers;
if (exists $ENV{GATEWAY_INTERFACE}
    && $ENV{GATEWAY_INTERFACE} =~ /^CGI-Perl\//) {
  require Apache;
  my $r = Apache->request or die;
  $r->send_cgi_header(join("\n", @{$result->{headers}})."\n");
}
else {
  print "$_\n" for @{$result->{headers}};
  print "\n";
}
print $result->{content};

sub get_class {
  my ($class, $cfg) = @_;

  (my $file = $class . ".pm") =~ s!::!/!g;
  eval {
    require $file;
  };
  if ($@) {
    print STDERR "Loading $class: $@\n";
    return;
  }
  return $class->new(cfg=>$cfg, db=>BSE::DB->single);
}

