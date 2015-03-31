package BSE::Formatter::Article;
use strict;
use base 'BSE::Formatter';
use BSE::Util::HTML;
use Digest::MD5 qw(md5_hex);

our $VERSION = "1.004";

sub rewrite_url {
  my ($self, $url, $text, $type) = @_;

  my $cfg = $self->{cfg};

  require BSE::URL;
  $url = BSE::URL->rewrite_url($cfg, $url);

  if ($self->{redirect_links} =~ /[^\W\d]/) {
    my $noredir_types = join '|', map quotemeta, split /,/, $self->{redirect_links};
    if ($url =~ /^($noredir_types):/) {
      return $self->SUPER::rewrite_url($url, $text, $type);
    }
  }
  elsif (!$self->{redirect_links} || $url =~ /^mailto:/ || $url =~ /^\#/) {
    return $self->SUPER::rewrite_url($url, $text, $type);
  }

  # formatter converted & to &amp; but we want them as & so they undergo
  # uri conversion correctly
  $url = unescape_html($url);
  $text = unescape_html($text);
  my $redir_hash = substr(md5_hex($url, $text, $self->{redirect_salt}), 0, 16);

  my $new_url = '/cgi-bin/nuser.pl/redirect?url='
    . escape_uri($url) . "&amp;h=$redir_hash";
  if ($url ne $text) {
    $new_url .= '&amp;title=' . escape_uri($text);
  }

  return $self->SUPER::rewrite_url($new_url, $text, $type);
}

1;
