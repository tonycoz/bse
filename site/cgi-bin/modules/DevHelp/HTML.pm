package DevHelp::HTML;
use strict;
use Carp qw(confess);

our $VERSION = "1.000";

require Exporter;
use vars qw(@EXPORT_OK @EXPORT @ISA %EXPORT_TAGS);
@EXPORT_OK = qw(escape_html escape_uri unescape_html unescape_uri popup_menu escape_xml);
@EXPORT = qw(escape_html escape_uri unescape_html unescape_uri);
%EXPORT_TAGS =
  (
   all => \@EXPORT_OK,
   default => \@EXPORT,
  );
@ISA = qw(Exporter);

use HTML::Entities ();
use URI::Escape ();

sub escape_html {
  my ($text, $what) = @_;

  $what ||= '<>&"\x7F';

  HTML::Entities::encode($text, $what);
}

sub unescape_html {
  HTML::Entities::decode(shift);
}

my %xml_entities = qw(< lt > gt & amp " quot);

sub escape_xml {
  my ($text) = @_;

  $text =~ s/([<>&\"\x7F])/$xml_entities{$1} ? "&$xml_entities{$1};" : "&#".ord($1).";"/ge;
  
  return $text;
}

sub escape_uri {
  # older versions of uri_escape() acted differently without the
  # second argument, so supply one to make sure we escape what
  # needs escaping
  URI::Escape::uri_escape(shift, "^A-Za-z0-9\-_.!~*()");
}

sub unescape_uri {
  URI::Escape::uri_unescape(shift);
}

sub _options {
  my ($values, $labels, $default) = @_;

  my $html = '';
  for my $value (@$values) {
    my $option = '<option value="' . escape_html($value) . '"';
    my $label = $labels->{$value};
    defined $label or $label = $value;
    $option .= ' selected="selected"'
      if defined($default) && $default eq $value;
    $option .= '>' . escape_html($label) . "</option>";
    $html .= $option . "\n";
  }

  return $html;
}

sub popup_menu {
  my (%opts) = @_;

  exists $opts{'-name'}
    or confess "No -name parameter";

  my $html = '<select name="' . escape_html($opts{"-name"}) . '"';
  $html .= ' id="'.escape_html($opts{'-id'}).'"' if $opts{'-id'};
  $html .= '>';
  my $labels = $opts{"-labels"} || {};
  my $values = $opts{"-values"};
  my $default = $opts{"-default"};
  my $groups = $opts{"-groups"};
  if ($groups) {
    for my $group (@$groups) {
      my ($label, $ids) = @$group;
      if (length $label) {
	$html .= '<optgroup label="' . escape_html($label) . '">'
	  . _options($ids, $labels, $default) . '</optgroup>';
      }
      else {
	$html .= _options($ids, $labels, $default);
      }
    }
  }
  else {
    $html .= _options($values, $labels, $default);
  }
  $html .= "</select>";

  $html;
}

1;

__END__

=head1 NAME

DevHelp::HTML - provides simple consistent interfaces to HTML/URI
escaping with some extras

=head1 SYNOPSIS

  use DevHelp::HTML;

  my $escaped = escape_html($text);
  my $escaped = escape_uri($text);
  my $unescaped = unescape_html($text);
  my $unescaped = unescape_uri($text);
  my $html = popup_menu(-name => $name,
                        -values => \@values,
			-labels => \%labels,
			-default => $default);

=head1 DESCRIPTION

Provides some of the functionality of the CGI.pm module, without the
code to get the query/POST parameters.

=over

=item escape_html($text)

Converts characters that should be entities into entities.  Don't
expect this to work with UTF-8 text.  Unlike the native HTML::Entities
interface it won't convert CR (\x0D) into an entity, since this causes
problems.

Probably assumes Latin-1.

=item escape_uti($text)

URI escapes $text.

=item unescape_html($text)

Unescape entities.

=item unescape_uri($text)

Unescape URI escaped text.

=item popup_menu(...)

Creates a C<select> form element.  Same interface as CGI::popup_menu()
but without the need to use -override to make the -default option
useful.

=back

=head1 AUTHOR

Tony Cook <tony@develop-help.com>

=cut
