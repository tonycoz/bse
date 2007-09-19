#!perl -w
# Bulk add image tool

use strict;
use LWP::UserAgent;
use HTTP::Cookies;
use Getopt::Long;
use HTTP::Request::Common;

my $verbose;
my $user;
my $password;
Getopt::Long::Configure('bundling');
GetOptions("v:i", \$verbose,
	   "u=s", \$user,
	   "p=s", \$password);
++$verbose if defined $verbose && !$verbose;

# should be 3 options - base url, article number, input file
# default to stdin if no input
my $base_url = shift;
my $article_id = shift;

defined $article_id
  or usage();
$article_id =~ /^(\d+|-1)$/ # -1 for global images
  or die "Invalid article id\n";

@ARGV or @ARGV = "-";

if ($user && !$password
    || $password && !$user) {
  die "-u and -p must both be supplied if either is\n";
}

my $ua = LWP::UserAgent->new;
$ua->cookie_jar(HTTP::Cookies->new);

if ($user) {
  print STDERR "Logging on\n" if $verbose;
  # go logon
  my $result = $ua->post("$base_url/cgi-bin/admin/logon.pl",
			 [ 
			  logon => $user,
			  password => $password,
			  a_logon => 1,
			  _service => 1,
			 ]);
  # we should see a refresh header on success
  service_result("Error logging on", $result);
}

# check we have a valid article
my $result = $ua->get("$base_url/cgi-bin/admin/admin.pl?id=$article_id");
# if the article doesn't exist, we're sent to the menu
if ($result->header("Refresh")) {
  die "Article $article_id doesn't exist\n";
}

# ok, start working on them
while (<>) {
  chomp;
  my ($filename, $alt) = split;

  open IMG, "<$filename" or die "Cannot open $filename: $!\n";
  binmode IMG;
  my $imdata = do { local $/; <IMG> };
  close IMG;

  print STDERR "Adding $filename / $alt" if $verbose;
  # make a request
  my $req = POST "$base_url/cgi-bin/admin/add.pl",
     [
      id => $article_id,
      image => [ undef, $filename, Content => $imdata ],
      altIn => $alt,
      url => '',
      name=> '',
      addimg => 1,
      level => 1,
      _service => 1,
     ],
     Content_Type => 'form-data';
  #print "Req", $req->as_string,"\n";
  my $result = $ua->request($req);

  my $serv_resp = service_result("\nError adding image", $result);
  print " - added as image $serv_resp->{image}\n" if $verbose;
}

sub usage {
  die <<EOS
Usage: $0 [-u user] [-p password] [-v verbosity] baseurl article id sources
EOS
}

sub service_result {
  my ($what, $http_result) = @_;

  $http_result->is_success
    or die "$what - http error: ", $http_result->status_line, "\n";

  my %result;
  my $content = $http_result->decoded_content;
  while ($content =~ s/^(\w+): *(.*)\n//) {
    $result{lc $1} = $2;
  }
  $result{result} eq 'success'
    or die "$what - service failure: ", $result{error}, "\n";

  \%result;
}
