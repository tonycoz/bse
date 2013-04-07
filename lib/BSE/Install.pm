package BSE::Install;
use strict;
use Exporter 'import';
our @EXPORT_OK = qw(cfg util_dir cgi_dir public_html_dir templates_dir data_dir mysql_name perl);
use lib 'site/cgi-bin/modules';
use BSE::Cfg;

our $VERSION = "1.000";

my $conffile = $ENV{BSECONFIG} || 'install.cfg';

my $cfg = BSE::Cfg->new
  (
   path => "site/cgi-bin",
   extra_file => $conffile,
  );

sub cfg {
  $cfg;
}

sub conffile {
  $conffile;
}

sub util_dir {
  $cfg->entryVar("paths", "util");
}

sub cgi_dir {
  $cfg->entryVar("paths", "cgi-bin");
}

sub public_html_dir {
  $cfg->entryVar("paths", "public_html");
}

sub templates_dir {
  $cfg->entryVar("paths", "templates");
}

sub data_dir {
  $cfg->entryVar("paths", "data");
}

sub mysql_name {
  $cfg->entry("binaries", "mysql", "mysql");
}

sub perl {
  $cfg->entry("paths", "perl", $^X);
}

sub db_dsn {
  $cfg->entryErr("db", "dsn");
}

sub db_user {
  $cfg->entryErr("db", "user");
}

sub db_password {
  $cfg->entryErr("db", "password");
}

1;
