package BSE::SubscriptionType;
use strict;
# represents a subscription type from the database
use Squirrel::Row;
use vars qw/@ISA/;
@ISA = qw/Squirrel::Row/;

sub columns {
  return qw/id name title description frequency keyword archive 
            article_template html_template text_template parentId lastSent
            visible/;
}

sub _build_article {
  my ($sub, $article, $opts) = @_;

  my @cols = Article->columns;
  shift @cols;
  @$article{@cols} = ('') x @cols;
  my $parentId = $opts->{parentId} || $sub->{parentId} || -1;
  my $parent;
  if ($parentId > 0) {
    $parent = Articles->getByPkey($parentId);
  }
  use BSE::Util::SQL qw(now_datetime now_sqldate);
  $article->{body} = $opts->{body} || '';
  $article->{title} = defined($opts->{title}) ? $opts->{title} : $sub->{title};
  $article->{parentid} = $opts->{parentId} || $sub->{parentId};
  $article->{displayOrder} = time;
  $article->{imagePos} = 'tr';
  $article->{release} = now_sqldate;
  $article->{expire} = $Constants::D_99;
  $article->{keyword} = 
    exists($opts->{keyword}) ? $opts->{keyword} : $sub->{keyword};
  $article->{generator} = 'Generate::Article';
  $article->{level} = $parent ? $parent->{level} + 1 : -1;
  $article->{listed} = 1;
  $article->{lastModified} = now_datetime;
  $article->{link} = '';

  my $template = $opts->{html_template};
  $template = $sub->{html_template} unless defined $template;
  $article->{template} = $template;
  $article->{generator} = 'Generate::Subscription';
  $article->{id} = -5;

  $article->{threshold} = 1;
#    $article->{titleImage} = '';
#    $article->{thumbImage} = '';
#    $article->{thumbWidth} = $article->{thumbHeight} = 0;

#    $article->{admin} = '';
#    $article->{link} = '';
}

sub _word_wrap {
  my ($text) = @_;

  $text =~ s/(.{1,72}\s+)(?=\S)/$1\n/g;

  $text;
}

sub _format_body {
  my ($cfg, $article) = @_;
  require 'Generate.pm';
  my $gen = Generate->new(cfg=>$cfg, top => $article);
  my $body = $article->{body};
  $gen->remove_block(\$body);
  1 while $body =~ s/[bi]\[([^\[\]]+)\]/$1/g;
  $body =~ tr/\r//d; # in case
  $body =~ s/(^(?:[ \t]*\n)?|\n[ \t]*\n)([^\n]{73,})(?=\n[ \t]*\n|\n?\z)/
    $1 . _word_wrap($2)/ge;

  $body;
}

sub _text_format_low {
  my ($sub, $cfg, $user, $opts, $article) = @_;

  my $template = $opts->{text_template} || $sub->{text_template};
  $article->{generator} = 'Generate::Subscription';
  $article->{id} = -5;
  my %acts;
  %acts =
    (
     BSE::Util::Tags->static(\%acts, $cfg),
     article=>sub { $article->{$_[0]} },
     ifUser => sub { $user },
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
  
  return BSE::Template->get_page($template, $cfg, \%acts);
}

sub text_format {
  my ($sub, $cfg, $user, $opts) = @_;

  my %article;
  $sub->_build_article(\%article, $opts);
  return $sub->_text_format_low($cfg, $user, $opts, \%article);
}

sub html_format {
  my ($sub, $cfg, $user, $opts) = @_;

  my %article;
  $sub->_build_article(\%article, $opts);
  require 'Generate/Subscription.pm';
  my $gen = Generate::Subscription->new(cfg=>$cfg, top => \%article);
  $gen->set_user($user);
  $gen->set_sub($sub);

  return $gen->generate(\%article, 'Articles');
}

sub recipients {
  my ($sub) = @_;

  require 'SiteUsers.pm';
  SiteUsers->getSpecial('subRecipients', $sub->{id});
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
  my $gen;
  if ($article->{template}) {
    #print STDERR "Making generator\n";
    require 'Generate/Subscription.pm';
    $gen = Generate::Subscription->new(cfg=>$cfg, top=>$article);
    $gen->set_sub($sub);
  }
  my $from = $cfg->entryIfVar('subscriptions', 'from');
  unless ($from) {
    $from = $Constants::SHOP_FROM;
  }
  unless ($from) {
    $callback->('error', undef, "Configuration error: No from address configured, please set from in the subscriptions section of the config file, or \$SHOP_FROM in Constants.pm");
    return;
  }
  my $charset = $cfg->entry('basic', 'charset') || 'iso-8859-1';
  my $index = 0;
  for my $user (@$recipients) {
    $callback->('user', $user) if $callback;
    my $text = $sub->_text_format_low($cfg, $user, $opts, $article);
    my $html;
    if ($gen && !$user->{textOnlyMail}) {
      #print STDERR "Making HTML\n";
      $gen->set_user($user);
      $html = $gen->generate($article, 'Articles');
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

sub send {
  my ($sub, $cfg, $opts, $callback) = @_;

  my @recipients = $sub->recipients;

  unless (@recipients) {
    $callback->('error', undef, 'This subscription has no recipients, no action taken');
    return;
  }

  my %article;
  $sub->_send($cfg, $opts, $callback, \@recipients, \%article);

  if (exists $opts->{archive} && $opts->{archive}
      || $sub->{archive}) {
    $callback->('general', undef, "Archiving article");
    require 'Articles.pm';
    $article{template} = $opts->{article_template} || $sub->{article_template};
    $article{generator} = 'Generate::Article';
    $article{parentid} = $opts->{parentId} || $sub->{parentId};
    my @cols = Article->columns;
    shift @cols;
    my $article = Articles->add(@article{@cols});
    use Constants qw(:edit $CGI_URI $IMAGES_URI $ARTICLE_URI $LINK_TITLES);
    my $link = "$ARTICLE_URI/$article->{id}.html";
    if ($LINK_TITLES) {
      (my $extra = lc $article->{title}) =~ tr/a-z0-9/_/sc;
      $link .= "/".$extra;
    }
    $article->{link} = $link;
    $article->setAdmin("$CGI_URI/admin/admin.pl?id=$article->{id}");
    $article->save;
    require 'Util.pm';
    
    $callback->('general', undef, "Generating article");
    Util::generate_article('Articles', $article, $cfg);
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
