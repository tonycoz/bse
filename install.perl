#!perl -w
use strict;
use Term::ReadLine;
use Config;
my $term = new Term::ReadLine "BSE Install";
use POSIX ();

$|=1;

unless ($term->ReadLine eq 'Term::ReadLine') {
  print "Happily, you may have a decent readline\n";
}
else {
  print "Sadly, you only have the basic readline stub installed\n";
}

print <<EOS;
BSE installation
================

This script will take you through installation of BSE.

If you want to perform an upgrade, change directory to the cgi-bin directory 
of the existing installation and run this script again.

Press Enter to continue (or Ctrl-C to abort).
EOS
<STDIN>;
++$|;

my %config;
my $upgrade;
if (-e 'modules/Constants.pm' && -e 'modules/Generate/Article.pm') {
  my $prompt = <<EOS;
An existing installation has been found.

Do you want to perform an upgrade?
EOS
  if (askYN($prompt, 1)) {
    
  }
}

my @conf_info =
  (
   DB => { desc => "Name of mysql database", cat=>'db', },
   UN => { desc => "Mysql database username", cat=>'db', },
   PW => { desc => "Mysql database password", cat=>'db', },
   BASEDIR => { desc=>"Base directory of installation", cat=>'dir', 
		help => <<EOS,
The directory that the other directories are based under.  This isn't
actually used directly, but can be used to help initialize the other 
directory names.

This must be an absolute directory.
EOS
	       val => \&is_absdir, def=>},
   TMPLDIR => { desc=>"Templates directory", cat=>'dir', 
		def=>'$BASEDIR/templates', help=><<EOS,
This is where page and email templates are stored.

This can be an absolute directory, or use ./foo to make it relative to
BASEDIR.
EOS
		val => \&is_abs_baserel },
   CONTENTBASE => { desc=>"Content directory", cat=>'dir',
		    def=>'$BASEDIR/htdocs', help=><<"EOS",
The base directory that contains your site content.  This must be the top 
directory of your site.

This can be an absolute directory, or use ./foo to make it relative to
BASEDIR.
EOS
		  val=>\&is_abs_baserel },
   IMAGEDIR => { desc => "Images directory", cat=>'dir',
		 def => '$CONTENTDIR/images', help => <<"EOS",

EOS
	       },
   DATADIR => { desc => "Data directory" },
  );

my %conf_info = @conf_info;
my @conf_order = grep !ref, @conf_info;



sub askYN {
  my ($query, $def) = @_;
  print $query;
  while (1) {
    print $def ? "[Y]" : "[N]",":";
    my $resp = $term->readline;
    return $def if $resp =~ /^\s*$/;
    return 1 if $resp =~ /y/i;
    return 0 if $resp =~ /n/i;
    print "Please enter yes or no ";
  }
}

sub askDir {
  my ($item) = @_;

  my $def;
  $item->{def} and ($def = $item->{def}) =~ s/\$(\w+)/$config{$1}/g;
  while (1) {
    my $resp = $term->readline($item->{desc}, $def);
    if ($resp eq 'help' || $resp eq '?') {
      print $item->{help} || "Sorry, no help for this item\n";
      next;
    }
    if ($item->{val}) {
      eval {
	$item->{val}->($resp);
      };
      if ($@) {
	print $@;
	next;
      }
    }
    return $resp;
  }
}

sub clear {
  if ($^O =~ /win32/i) {
    system "cls";
  }
  else {
    system "clear";
  }
}
