package BSE::Util::Fetcher;
use strict;
use warnings;
use BSE::TB::Articles;
use BSE::TB::AuditLog;
use LWP::UserAgent;
use BSE::Util::HTML "escape_uri";
use JSON ();

our $VERSION = "1.002";

my $json_types = qq!\\A(?:application/json|text/x-json(?: encoding=(?:"utf-8"|utf-8)?))\\z!;

sub new {
  my ($class, %opts) = @_;

  if ($opts{articles}) {
    $opts{harticles} = +{ map { $_ => 1 } @{$opts{articles}} };
  }
  $opts{report} ||= sub { print "@_\n" };

  bless \%opts, $class;
}

sub run {
  my ($self) = @_;

  $self->{errors} = [];

  my $cfg = $self->{cfg};
  my $section = $self->{section};
  my $verbose = $self->{verbose};
  my $report = $self->{report};

  unless ($cfg->entry("basic", "access_control", 0)) {
    $self->crit(undef, undef, undef,
		"Access control must be enabled for fetch processing");
    return;
  }

  my %entries = $cfg->entries($section);
  my @data_keys = grep /^data/i, keys %entries;

 KEY:
  for my $key (@data_keys) {
    (my $suffix = $key) =~ s/^data//i;

    my $data_name = $cfg->entryErr($section, $key);
    my $bad_cfg = 0;
    unless ($data_name =~ /^([a-zA-Z0-9_-]+)$/) {
      $self->crit(undef, undef, undef,
		  "Invalid metadata name '$data_name' for [$section].$key");
      ++$bad_cfg;
    }
    my $url_name = $cfg->entry($section, "url$suffix", "${data_name}_url");
    unless ($url_name =~ /^([a-zA-Z0-9_-]+)$/) {
      $self->crit(undef, undef, undef,
		  "Invalid metadata url '$url_name' for [$section].url$suffix");
      ++$bad_cfg;
    }
    my $url_pattern = $cfg->entry($section, "url_pattern$suffix", '$s');
    unless ($url_pattern =~ /\$s/) {
      $self->crit(undef, undef, undef,
		  "Invalid url pattern '$url_pattern' for [$section].url_pattern$suffix");
      ++$bad_cfg;
    }
    my $url_escape = $cfg->entry($section, "url_escape$suffix", 0);
    my $types = $cfg->entry($section, "types$suffix", $json_types);
    my $types_re;
    unless (eval { $types_re = qr/$types/; 1 }) {
      $self->crit(undef, undef, undef,
		  "Cannot compile regexp /$types/ for [$section].types$suffix: $@");
      ++$bad_cfg;
    }
    my $validate = $cfg->entry($section, "validate$suffix", "json");
    unless ($validate =~ /\A(?:json|none)\z/i) {
      $self->crit(undef, undef, undef,
		  "Invalid validate '$validate' value for [$section].validate$suffix");
      ++$bad_cfg;
    }
    my $max_length = $cfg->entry($section, "max_length$suffix", 1_000_000);
    unless ($max_length =~ /\A[1-9][0-9]+\z/) {
      $self->crit(undef, undef, undef,
		  "Invalid max_length '$max_length' value for [$section].max_length$suffix");
      ++$bad_cfg;
    }
    my $on_fail = $cfg->entry($section, "on_fail$suffix", "delete");
    unless ($on_fail =~ /\A(delete|keep)\z/i) {
      $self->crit(undef, undef, undef,
		  "Invalid on_fail '$on_fail' value for [$section].on_fail$suffix");
      ++$bad_cfg;
    }
    my $on_success = $cfg->entry($section, "on_success$suffix", "");
    unless ($on_success =~ /\A(?:|(?&KEY)(?:,(?&KEY))*)\z
			   (?(DEFINE)
			     (?<KEY>log)
			   )/xi) {
      $self->crit(undef, undef, undef,
		  "Invalid on_success '$on_success' value for [$section].on_success$suffix");
      ++$bad_cfg;
    }
    $bad_cfg and next KEY;

    my %cfg_dump =
      (
       data_name => $data_name,
       url_name => $url_name,
       url_pattern => $url_pattern,
       url_escape => $url_escape,
       types => $types,
       validate => $validate,
       max_length => $max_length,
       on_fail => $on_fail,
       on_success => $on_success,
      );

    my $ua = LWP::UserAgent->new;

    # look for articles with the url metadata defined
    my @meta = BSE::TB::Article->all_meta_by_name($url_name);
  META:
    for my $meta (@meta) {
      length $meta->value
	or next;
      if ($self->{harticles} && !$self->{harticles}{$meta->file_id}) {
	next META;
      }
      my ($article) = BSE::TB::Articles->getByPkey($meta->file_id)
	or next META;

      my %base_dump =
	(
	 %cfg_dump,
	 article => $article->id,
	);

      unless ($meta->is_text_type) {
	$self->fail($article, $data_name, $on_fail,
		    "Metadata $url_name for article " . $meta->file_id . " isn't text");
	next META;
      }

      my $url_part = $meta->value_text;
      $url_part =~ /\S/ or next META;
      $url_escape and $url_part = escape_uri($url_part);
      (my $url = $url_pattern) =~ s/\$s/$url_part/;

      unless ($url =~ /\A(?:https?|ftp):/) {
	$self->fail($article, $data_name, $on_fail, "$url isn't http, https or ftp",
		   \%base_dump);
	next META;
      }

      $report->("$data_name: fetching $url") if $verbose;
      $base_dump{url} = $url;
      my $resp = $ua->get($url);
      unless ($resp->is_success) {
	print "  fetch failed: ", $resp->status_line, "\n" if $verbose;
	$self->fail($article, $data_name, $on_fail,
		    "Error fetching $url: " . $resp->status_line,
		    +{
		      %base_dump,
		      status => scalar $resp->status_line,
		     });
	next META;
      }
      $resp->decode;
      # we don't want character set decoding, just raw content after
      # decompression
      my $content = $resp->content;
      unless (length($content) <= $max_length) {
	$report->("  response too long") if $verbose;
	$self->fail($article, $data_name, $on_fail,
		    "Content is ".length($content)." which is larger than $max_length",
		    +{
		      %base_dump,
		      length => length($content),
		     });
	next META;
      }
      unless ($resp->content_type =~ $types_re) {
	$report->("  Invalid content type", $resp->content_type) if $verbose;
	$self->fail($article, $data_name, $on_fail,
		    "Content type '".$resp->content_type()."' doesn't match the types regexp",
		    +{
		      %base_dump,
		      content_type => $resp->content_type,
		     });
	next META;
      }
      if ($validate eq 'json') {
	my $json = JSON->new;
	unless (eval { $json->decode($content); 1 }) {
	  $report->("  Failed JSON validation") if $verbose;
	  $self->fail($article, $data_name, $on_fail,
		      "Content failed JSON validation", \%base_dump);
	  next META;
	}
      }

      if ($self->{save}) {
	my $data = $article->meta_by_name($data_name);
	if ($data) {
	  $data->set_content_type($resp->content_type);
	  $data->set_value($content);
	  $data->save;
	}
	else {
	  $data = $article->add_meta
	    (
	     name => $data_name,
	     content_type => scalar $resp->content_type,
	     value => $content,
	     appdata => 1,
	    );
	}
	$report->("  Saved") if $verbose;
	if ($on_success =~ /\blog\b/i) {
	  BSE::TB::AuditLog->log
	      (
	       component => "fetcher::run",
	       level => "info",
	       actor => "S",
	       msg => "Successfully saved '$data_name' for article '".$article->id."'",
	       object => $article,
	       dump => \%base_dump,
	      );
	}
      }
    }
  }

  return !@{$self->{errors}};
}

sub errors {
  my $self = shift;
  $self->{errors};
}

sub fail {
  my $self = shift;
  my ($article, $data_name, $on_fail) = @_;
  $self->_log("error", @_);

  if ($article && $on_fail eq "delete" && $self->{save}) {
    $article->delete_meta_by_name($data_name);
  }
}

sub crit {
  my $self = shift;
  $self->_log("crit", @_);
}

sub _log {
  my ($self, $level, $article, $data_name, $on_fail, $message, $dump) = @_;

  push @{$self->{errors}}, [ $level, $message ];
  if ($self->{log}) {
    BSE::TB::AuditLog->log
	(
	 component => "fetcher::run",
	 level => $level,
	 actor => "S",
	 msg => $message,
	 object => $article,
	 dump => $dump,
	);
  }
}
