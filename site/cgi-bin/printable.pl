#!/usr/bin/perl -w
use strict;
use CGI qw(:standard);
use Carp; # 'verbose'; # remove the 'verbose' in production
use lib 'modules';
use Articles;
use Constants qw($TMPLDIR);
use Squirrel::Template;

my $id = param('id');
defined $id or $id = 1;
# the reason to avoid creating an articles object is that this
# loads all of the articles into memory
# hopefully a print template won't include too many references to 
# other articles anyway
#my $articles = Articles->new;

my $article = Articles->getByPkey($id)
  or error_page("No article with id $id found");

eval "use $article->{generator}";
die $@ if $@;
my $generator = $article->{generator}->new(articles=>'Articles');

my $template = param('template');

# make sure they don't try to work outside the 
my $file;
if ($template) {
  if ($template =~ m!^/! || $template =~ /\.\./ || $template !~ /\.tmpl$/i) {
    error_page("Invalid template name '$template'");
  }

  -e file_from_template($template) 
    or error_page("Cannot find template '$template'");
}
else {
  for my $work ($article->{template}, 'printable.tmpl') {
    next unless $work =~ /\S/;
    $template = $work;
    $file = file_from_template($work);
    last if -e $file;
  }
  -e $file or error_page("No template available for this page");
}

open TMPLT, "< $file"
  or error_page("Cannot open template '$template'");
my $text = do { local $/; <TMPLT> };
close TMPLT;

$text =~ s/<:\s*embed\s+(?:start|end)\s*:>//g;

print "Content-Type: text/html\n\n";
print $generator->generate_low($text, $article, 'Articles');

sub error_page {
  my ($error) = @_;
  $error ||= "Unknown error";

  require 'Generate.pm';
  my $gen = Generate->new();
  my %acts;
  %acts = 
    (
     $gen->baseActs('Articles', \%acts),
     error => sub { CGI::escapeHTML($error) },
    );
  print "Content-Type: text/html\n\n";
  print Squirrel::Template->new(template_dir=>$TMPLDIR)
    ->show_page($TMPLDIR, 'error.tmpl', \%acts);
  exit;
}

sub file_from_template {
  my ($template) = @_;

  my $file = $TMPLDIR;
  $file .= "/" unless $file =~ m![\\/]$!;
  $file .= "printable/";
  $file .= $template;

  return $file;
}
