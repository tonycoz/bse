package DevHelp::HTML;
use strict;
use Carp qw(confess);

require Exporter;
use vars qw(@EXPORT_OK @EXPORT @ISA);
@EXPORT_OK = qw(escape_html escape_uri unescape_html unescape_uri popup_menu);
@EXPORT = qw(escape_html escape_uri unescape_html unescape_uri);
@ISA = qw(Exporter);

use HTML::Entities ();
use URI::Escape ();

sub escape_html {
  HTML::Entities::encode(shift, '<>&"\x7F-\xFF');
}

sub unescape_html {
  HTML::Entities::decode(shift);
}

sub escape_uri {
  URI::Escape::uri_escape(shift);
}

sub unescape_uri {
  URI::Escape::uri_unescape(shift);
}

sub popup_menu {
  my (%opts) = @_;

  exists $opts{'-name'}
    or confess "No -name parameter";

  my $html = '<select name="' . escape_html($opts{"-name"}) . '">';
  my $labels = $opts{"-labels"} || {};
  my $values = $opts{"-values"};
  my $default = $opts{"-default"};
  for my $value (@$values) {
    my $option = "<option";
    my $label = $labels->{$value};
    if (defined $label) {
      $option .= ' value="' . escape_html($value) . '"';
      $option .= ' checked' if defined($default) && $default eq $value;
      $option .= '>' . escape_html($label);
    }
    else {
      $option .= ' checked' if defined($default) && $default eq $value;
      $option .= '>' . escape_html($value);
    }
    $html .= $option . "\n";
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
