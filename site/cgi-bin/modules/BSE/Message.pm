package BSE::Message;
use strict;
use Carp qw/confess/;
use BSE::DB;
use BSE::Cfg;
use BSE::Cache;
use DevHelp::HTML;
use Scalar::Util qw(reftype blessed);
use overload 
  "&{}" => sub { my $self = $_[0]; return sub { $self->_old_msg(@_) } },
  "bool" => sub { 1 };

our $VERSION = "1.007";

my $single;

=head1 NAME

BSE::Message - BSE message catalog access.

=head1 SYNOPSIS

  my $msgs = BSE::Message->new;
  my $text = $msgs->text($lang, $msgid);
  my $text = $msgs->text($lang, $msgid, [ parameters ]);
  my $text = $msgs->text($lang, $msgid, [ parameters ], $def);
  my $html = $msgs->html($lang, $msgid);
  my $html = $msgs->html($lang, $msgid, [ parameters ]);
  my $html = $msgs->html($lang, $msgid, [ parameters ], $def);

=cut

sub _new {
  my ($class, %opts) = @_;

  return bless
    {
     cache_age => BSE::Cfg->single->entry("messages", "cache_age", 60),
     mycache => {},
     cache => scalar(BSE::Cache->load),
    }, $class;
}

sub new {
  my ($class, %opts) = @_;

  $single ||= $class->_new;

  if ($opts{section}) {
    $single->{section} = $opts{section};
  }

  return $single;
}

sub text {
  my ($self, $lang, $msgid, $parms, $def) = @_;

  $msgid =~ s/^msg://;

  ref $self or $self = $self->new;

  my $msg = $self->_get_replaced($lang, $msgid, $parms);
  if ($msg) {
    if ($msg->{formatting} eq 'body') {
      require BSE::Formatter;
      my $formatter = BSE::Formatter->new;
      return $formatter->remove_format($msg->{message});
    }

    return $msg->{message};
  }
  else {
    $def and return $def;
    return;
  }
}

sub html {
  my ($self, $lang, $msgid, $parms, $def) = @_;

  $msgid =~ s/^msg://;

  ref $self or $self = $self->new;

  my $msg = $self->_get_replaced($lang, $msgid, $parms);
  if ($msg) {
    if ($msg->{formatting} eq 'body') {
      require BSE::Generate;
      require BSE::Template;
      my $gen = Generate->new(cfg => BSE::Cfg->single);
      my $templater = BSE::Template->templater(BSE::Cfg->single);
      return $gen->format_body(acts => {},
			       articles => "Articles",
			       text => $msg->{message},
			       templater => $templater);
    }

    return escape_html($msg->{message});
  }
  else {
    $def and return $def;
    return;
  }
}

=item $self->get_replaced($lang, $msgid, $parms)

Retrieve the base message text + formatting info, and replace parameters.

Currently just replaces parameters, should also:

=over

=item *

have a mechanism to replace messages eg.

  %msg{bse/bar}

=item *

have a zero/single/plural mechanism, eg.:

  %c1{zero text;single text;multiple text}

=back

=cut

sub _get_replaced {
  my ($self, $lang, $msgid, $parms) = @_;

  my $msg = $self->_get_base($lang, $msgid)
    or return;

  $parms ||= [];
  $msg->{message} =~ s/%(%|[0-9]+:(?:\{\w+\})?[-+ #0]?[0-9]*(?:\.[0-9]+)?[duoxXfFeEgGs])/
    $1 eq "%" ? "%" : $self->_value($msg, $1, $parms)/ge;

  return $msg;
}

sub _value {
  my ($self, $msg, $code, $parms) = @_;

  my ($index, $format) = $code =~ /^([0-9]+):(.*)$/;
  $index >= 1 && $index <= @$parms
    or return "(bad index $index in %$code)";

  my $method = "describe";
  if ($format =~ s/^\{(\w+)\}//) {
    my $work = $1;
    unless ($work =~ /^(remove|save|new)$/) {
      $method = $work;
    }
  }

  my $value = $parms->[$index-1];
  if (ref $value) {
    local $@;
    if (blessed $value) {
      my $good = eval { $value = $value->$method; 1; };
      unless ($good) {
	return "(Bad parameter $index - blessed but no $method)";
      }
    }
    elsif (reftype $value eq "HASH") {
      defined $value->{$method}
	or return "(Unknown key $method for $index)";
      $value = $value->{$method};
    }
    else {
      return "(Can't handle ".reftype($value)." values)";
    }
  }

  return sprintf "%$format", $value;
}

=item $self->get_base($lang, $msgid)

Retrieve the base message text + formatting info.

=cut

sub _get_base {
  my ($self, $lang, $msgid) = @_;

  defined $lang or $lang = BSE::Cfg->single->entry("basic", "language_code", "en");

  if ($self->{cache_age} == 0) {
    return $self->_get_base_low($lang, $msgid);
  }

  my $key = "$lang.$msgid";
  my $entry = $self->{mycache}{$key};
  if (!$entry && $self->{cache}) {
    $entry = $self->{cache}->get("msg-$key");
  }

  my $now = time;
  if ($entry) {
    if ($entry->[0] < $now - $self->{cache_age}) {
      undef $entry;
    }
  }

  if ($entry) {
    # clone the entry so text replacement doesn't mess us up
    $entry->[1] or return;
    my %entry = %{$entry->[1]};
    return \%entry;
  }

  my $msg = $self->_get_base_low($lang, $msgid);
  $entry = [ $now, $msg ];
  $self->{mycache}{$key} = $entry;
  if ($self->{cache}) {
    $self->{cache}->set("msg-$key", $entry);
  }

  $msg or return;

  # clone so the caller doesn't modify cached value
  my %entry = %$msg;
  return \%entry;
}

sub _get_base_low {
  my ($self, $lang, $msgid) = @_;

  # build a list of languages to search
  my @langs = $lang;
  if ($lang =~ /^([a-z]+(?:[a-z]+))\./) {
    push @langs, $1;
  }
  if ($lang =~ /^([a-z]+)_/i) {
    push @langs, $1;
  }

  my $msg;
  for my $search_lang (@langs) {
    ($msg) = BSE::DB->query(bseGetMsgManaged => $msgid, $search_lang)
      and return $msg;
  }

  for my $search_lang (@langs) {
    ($msg) = BSE::DB->query(bseGetMsgDefault => $msgid, $search_lang)
      and return $msg;
  }

  for my $fallback ($self->fallback) {
    ($msg) = BSE::DB->query(bseGetMsgManaged => $msgid, $fallback)
      and return $msg;

    ($msg) = BSE::DB->query(bseGetMsgDefault => $msgid, "")
      and return $msg;
  }

  return;
}

sub _old_msg {
  my ($self, $msgid, $def, @parms) = @_;

  my $msg = BSE::Cfg->single->entry("messages", "$self->{section}/$msgid");
  if ($msg) {
    $msg =~ s/\$([\d\$])/$1 eq '$' ? '$' : $parms[$1-1]/eg;
    return $msg;
  }

  $msgid = "bse/$self->{section}/$msgid";
  my $text = $self->text(undef, $msgid, \@parms);
  $text and return $text;

  return $def;
}

sub languages {
  my ($self) = @_;

  my $cfg = BSE::Cfg->single;
  my %langs = $cfg->entries("languages");
  delete $langs{fallback};
  $langs{en} ||= "English";
  my @langs = map +{ id => $_, name => $langs{$_} }, sort keys %langs;

  return @langs;
}

sub fallback {
  my ($self) = @_;

  my $cfg = BSE::Cfg->single;
  my $fallback = $cfg->entry("languages", "fallback", "en");
  return split /,/, $fallback;
}

sub uncache {
  my ($self, $id) = @_;

  ref $self or $self = $self->new;

  my $cache = $self->{cache}
    or return;

  for my $lang ($self->languages) {
    $cache->delete("msg-$lang->{id}.$id");
  }
}

1;
