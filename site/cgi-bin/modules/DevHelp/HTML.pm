package DevHelp::HTML;
use strict;
use Carp qw(confess);

require Exporter;
use vars qw(@EXPORT_OK @EXPORT @ISA);
@EXPORT_OK = qw(escape_html escape_uri unescape_html unescape_uri popup_menu);
@EXPORT = qw(escape_html escape_uri unescape_html unescape_uri);
@ISA = qw(Exporter);

use HTML::Entities ();

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
}

1;
