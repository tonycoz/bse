package BSE::SubscriptionType;
use strict;
# represents a subscription type from the database
use Squirrel::Row;
use vars qw/@ISA/;
@ISA = qw/Squirrel::Row/;

our $VERSION = "1.008";

sub columns {
  return qw/id name title description frequency keyword archive 
            article_template html_template text_template parentId lastSent
            visible/;
}

sub _build_article {
  my ($sub, $article, $opts) = @_;

  my @cols = BSE::TB::Article->columns;
  shift @cols;
  @$article{@cols} = ('') x @cols;
  my $parent_id = $opts->{parentId} || $sub->{parentId} || -1;
  my $parent;
  if ($parent_id > 0) {
    $parent = BSE::TB::Articles->getByPkey($parent_id);
    unless ($parent) {
      $parent_id = -1;
    }
  }
  use BSE::Util::SQL qw(now_datetime now_sqldate);
  $article->{body} = $opts->{body} || '';
  $article->{title} = defined($opts->{title}) ? $opts->{title} : $sub->{title};
  $article->{parentid} = $parent_id;
  $article->{displayOrder} = time;
  $article->{imagePos} = 'tr';
  $article->{release} = now_sqldate;
  $article->{expire} = $Constants::D_99;
  $article->{keyword} = 
    exists($opts->{keyword}) ? $opts->{keyword} : $sub->{keyword};
  $article->{generator} = 'BSE::Generate::Article';
  $article->{level} = $parent ? $parent->{level} + 1 : 1;
  $article->{listed} = 1;
  $article->{lastModified} = now_datetime;
  $article->{link} = '';

  my $template = $opts->{html_template};
  $template = $sub->{html_template} unless defined $template;
  $article->{template} = $template;
  $article->{generator} = 'BSE::Generate::Subscription';
  $article->{id} = -5;

  $article->{threshold} = $parent->{threshold};
  $article->{inherit_siteuser_rights} = 1;
  $article->{summaryLength} = $parent->{summaryLength};
  $article->{created} = now_datetime;
  $article->{inherit_siteuser_rights} = 1;
  $article->{force_dynamic} = 0;
  $article->{cached_dynamic} = 0;
  $article->{menu} = 0;
  
  # for field value neatness
  $article->{customDate1} = undef;
  $article->{customDate2} = undef;
  $article->{customStr1} = undef;
  $article->{customStr2} = undef;
  $article->{customInt1} = undef;
  $article->{customInt2} = undef;
  $article->{customInt3} = undef;
  $article->{customInt4} = undef;

#    $article->{titleImage} = '';
#    $article->{thumbImage} = '';
#    $article->{thumbWidth} = $article->{thumbHeight} = 0;

#    $article->{admin} = '';
#    $article->{link} = '';
}

sub _word_wrap {
  my ($text) = @_;

  my $out = '';
  while (length $text > 72) {
    $text =~ s/^(.{1,72}\s+)(?=\S)//
      or $text =~ s/^(\S+\s+)(?=\S)//
	or last;
    $out .= "$1\n";
  }
  $out .= $text;

  return $out;
  #$text =~ s/(.{1,72}\s+)(?=\S)/$1\n/g;

  #$text;
}

sub _format_link {
  my ($cfg, $url, $title, $index) = @_;

  my $fmt = $cfg->entry('subscriptions', 'text_link_inline',
			'$1 [$3]');
  my %replace = 
    (
     1 => $title,
     2 => $url,
     3 => $index,
     '$' => '$',
    );

  $fmt =~ s/\$([123\$])/$replace{$1}/g;
  
  $fmt;
}

sub _body_link {
  my ($cfg, $urls, $url, $title, $rindex) = @_;

  push @$urls, [ $url, $title ];

  return _format_link($cfg, $url, $title, $$rindex++);
}

sub _doclink {
  my ($cfg, $urls, $id, $title, $rindex) = @_;

  my $dispid;
  if ($id =~ /^\d+$/) {
    $dispid = $id;
  }
  else {
    # try to find it in the config
    my $work = $cfg->entry('articles', $id);
    unless ($work) {
      return ">> No article name '$id' in the [articles] section of bse.cfg <<";
    }
    $dispid = "$id ($work)";
    $id = $work;
  }
  require BSE::TB::Articles;
  my $art = BSE::TB::Articles->getByPkey($id);
  unless ($art) {
    return ">> Cannot find article id $dispid <<";
  }

  # make the URL absolute
  my $url = $art->{link};
  $url = $cfg->entryErr('site', 'url') . $url
    unless $url =~ /^\w+:/;

  unless ($title) {
    $title = $art->{title};
  }

  push @$urls, [ $url, $title ];

  return _format_link($cfg, $url, $title, $$rindex++);
}

sub _any_link {
  my ($cfg, $urls, $type, $content, $rindex) = @_;

  if (lc $type eq 'link') {
    if ($content =~ /^([^|]+)\|(.*)$/) {
      return _body_link($cfg, $urls, $1, $2, $rindex);
    }
    else {
      return $content;
    }
  }
  else { # must be doclink
    if ($content =~ /^([^|]+)\|(.*)$/) {
      return _doclink($cfg, $urls, $1, $2, $rindex);
    }
    else {
      return _doclink($cfg, $urls, $content, undef, $rindex);
    }
  }
}

sub _url_list {
  my ($cfg, $urls) = @_;
  
  my $url_fmt = $cfg->entry('subscriptions', 'text_link_list',
			    '[$3] $2');
  my $body = '';
  length $url_fmt
    or return $body;
  my $sep = $cfg->entry('subscriptions', 'text_link_list_prefix',
			'-----');
  $sep =~ s/\$n/\n/g;
  $body .= $sep . "\n" if length $sep;
  my $url_index = 1;
  for my $url (@$urls) {
    my %replace =
      (
       1 => $url->[1],
       2 => $url->[0],
       3 => $url_index,
       '$' => '$',
       'n' => "\n",
      );
    (my $work = $url_fmt) =~ s/\$([123\$n])/$replace{$1}/g;
    $body .= "$work\n";
    ++$url_index;
  }
  
  return $body;
}

sub _format_body {
  my ($cfg, $article) = @_;
  require BSE::Generate;
  my $gen = BSE::Generate->new(cfg=>$cfg, top => $article);
  my $body = $article->{body};
  my @urls;
  my $url_index = 1;
  while ($body =~ s#(?:pop)?(doclink|link)\[([^\]\[]+)\]#_any_link($cfg, \@urls, $1, $2, \$url_index)#ie) {
  }

  $gen->remove_block('BSE::TB::Articles', [], \$body);
  while (1) {
    $body =~ s/[bi]\[([^\[\]]+)\]/$1/g
       and next;
    $body =~ s#(?<=\W)\[([^\]\[]+)\]#\003$1\004#g
      and next;

    last;
  }
  $body =~ tr/\003\004/[]/;
  $body =~ tr/\r//d; # in case
  $body =~ s/(^(?:[ \t]*\n)?|\n[ \t]*\n)([^\n]{73,})(?=\n[ \t]*\n|\n?\z)/
    $1 . _word_wrap($2)/ge;

  if (@urls) {
    $body .= "\n" unless $body =~ /\n$/;
    $body .= _url_list($cfg, \@urls);
  }

  $body;
}

sub _text_format_low {
  my ($sub, $cfg, $user, $opts, $article) = @_;

  my $template = $opts->{text_template} || $sub->{text_template};
  $article->{generator} = 'BSE::Generate::Subscription';
  $article->{id} = -5;
  my %acts;
  %acts =
    (
     BSE::Util::Tags->static(\%acts, $cfg),
     article=>sub { $article->{$_[0]} },
     ifUser => 
     sub { 
       my ($args) = @_;
       $user or return '';
       defined $user->{$args} or return '';
       $user->{$args};
     },
     user =>
     sub {
       $user or return '';
       defined $user->{$_[0]} or return '';
       $user->{$_[0]}
     },
     body =>
     sub {
       _format_body($cfg, $article);
     },
     sub => sub { $sub->{$_[0]} },
    );
  
  require BSE::Template;
  return BSE::Template->get_page($template, $cfg, \%acts);
}

sub text_format {
  my ($sub, $cfg, $user, $opts) = @_;

  my %article;
  $sub->_build_article(\%article, $opts);
  require BSE::DummyArticle;
  bless \%article, "BSE::DummyArticle";
  return $sub->_text_format_low($cfg, $user, $opts, \%article);
}

sub html_format {
  my ($sub, $cfg, $user, $opts) = @_;

  my %article;
  $sub->_build_article(\%article, $opts);
  require BSE::Generate::Subscription;
  require BSE::DummyArticle;
  bless \%article, "BSE::DummyArticle";
  my $gen = BSE::Generate::Subscription->new(cfg=>$cfg, top => \%article);
  $gen->set_user($user);
  $gen->set_sub($sub);

  return $gen->generate(\%article, 'BSE::TB::Articles');
}

sub recipients {
  my ($sub) = @_;

  require BSE::TB::SiteUsers;
  BSE::TB::SiteUsers->getSpecial('subRecipients', $sub->{id});
}

sub recipient_count {
  my ($sub) = @_;

  my @rows = BSE::DB->query(subRecipientCount => $sub->{id});
  $rows[0]{count};
}

sub _send {
  my ($sub, $cfg, $opts, $callback, $recipients, $article) = @_;

  $callback->('general', undef, scalar(@$recipients)." recipients to process");
  require 'BSE/Mail.pm';
  my $mailer = BSE::Mail->new(cfg=>$cfg);
  $sub->_build_article($article, $opts);
  require BSE::DummyArticle;
  bless $article, "BSE::DummyArticle";
  my $gen;
  if ($article->{template}) {
    #print STDERR "Making generator\n";
    require BSE::Generate::Subscription;
    $gen = BSE::Generate::Subscription->new(cfg=>$cfg, top=>$article);
    $gen->set_sub($sub);
  }
  my $from = $cfg->entryIfVar('subscriptions', 'from');
  unless ($from) {
    $from = $cfg->entry('shop', 'from', $Constants::SHOP_FROM);
  }
  unless ($from) {
    $callback->('error', undef, "Configuration error: No from address configured, please set from in the subscriptions section of the config file, or \$SHOP_FROM in Constants.pm");
    return;
  }
  my $charset = $cfg->charset;
  my $index = 0;
  for my $user (@$recipients) {
    $callback->('user', $user) if $callback;
    my $text = $sub->_text_format_low($cfg, $user, $opts, $article);
      if ($cfg->utf8) {
	require Encode;
	$text = Encode::encode($cfg->charset, $text);
      }
    my $html;
    if ($gen && !$user->{textOnlyMail}) {
      #print STDERR "Making HTML\n";
      $gen->set_user($user);
      my %acts;
      %acts = $gen->baseActs("BSE::TB::Articles", \%acts, $article);
      $html = BSE::Template->get_page($article->template, $cfg, \%acts,
				      undef, undef, $gen->variables);
      if ($cfg->utf8) {
	require Encode;
	$html = Encode::encode($cfg->charset, $html);
      }
    }
    my @headers;
    my $content;
    push(@headers, "MIME-Version: 1.0");
    if ($html) {
      $html =~ tr/\cM/\cJ/;
      my $boundary = "====" . time . "=_=" .int(rand(10000))."=";
      push(@headers, qq!Content-Type: multipart/alternative; boundary="$boundary"!);
      $content = "This is a multi-part message in MIME format\n\n"
	. "--$boundary\n";
      $content .= qq!Content-Type: text/plain; charset="$charset"\n\n!
	. $text . "\n\n";
      $content .= "--$boundary\n";
      $content .= qq!Content-Type: text/html; charset="$charset"\n\n!
	. $html . "\n\n";
      $content .= "--$boundary--\n";
    }
    else {
      push(@headers, qq!Content-Type: text/plain; charset="$charset"!);
      $content = $text;
      $content .= "\n" unless $content =~ /\n$/;
    }
    unless ($mailer->send(from	  =>$from, 
			  to	  =>$user->{email},
			  subject =>$article->{title}, 
			  headers =>join("\n", @headers, ""),
			  body	  =>$content)) {
      $callback->('error', $user, scalar($mailer->errstr));
    }
    ++$index;
  }
}

# filter is an optional array ref of permitted subscriber ids
sub send {
  my ($sub, $cfg, $opts, $callback, $filter) = @_;

  my @recipients = $sub->recipients;

  unless (@recipients) {
    $callback->('error', undef, 'This subscription has no recipients, no action taken');
    return;
  }

  # filter the recipients
  if ($filter) {
    my %filter = map { $_=>1 } @$filter;
    @recipients = grep $filter{$_->{id}}, @recipients;

    unless (@recipients) {
      $callback->('error', undef, 'This subscription has no recipients after filters, no action taken');
      return;
    }
  }

  my %article;
  $sub->_send($cfg, $opts, $callback, \@recipients, \%article);

  if (exists $opts->{archive} ? $opts->{archive} : $sub->{archive}) {
    $callback->('general', undef, "Archiving article");
    require BSE::TB::Articles;
    $article{template} = $opts->{article_template} || $sub->{article_template};
    $article{generator} = 'BSE::Generate::Article';
    $article{parentid} = $opts->{parentId} || $sub->{parentId};
    my @cols = BSE::TB::Article->columns;
    shift @cols;
    my $article = BSE::TB::Articles->add(@article{@cols});
    use Constants qw(:edit $CGI_URI $ARTICLE_URI $LINK_TITLES);
    my $link = "$ARTICLE_URI/$article->{id}.html";
    if ($LINK_TITLES) {
      (my $extra = lc $article->{title}) =~ tr/a-z0-9/_/sc;
      $link .= "/".$extra;
    }
    $article->{link} = $link;
    $article->setAdmin("$CGI_URI/admin/admin.pl?id=$article->{id}");
    $article->save;
    require BSE::Regen;
    
    $callback->('general', undef, "Generating article");
    BSE::Regen::generate_article('BSE::TB::Articles', $article, $cfg);
  }

  use BSE::Util::SQL qw/now_datetime/;
  $sub->{lastSent} = now_datetime;
  $sub->save;
}

sub send_test {
  my ($sub, $cfg, $opts, $callback, $recipient) = @_;

  my @recipients = ( $recipient );

  my %article;
  $sub->_send($cfg, $opts, $callback, \@recipients, \%article);
}

1;
