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
  $article->{title} = $opts->{title} || $sub->{title};
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
  my ($cfg, $body) = @_;
  require 'Generate.pm';
  my $gen = Generate->new(cfg=>$cfg);
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
       _format_body($cfg, $article->{body});
     },
     sub => sub { $sub->{$_[0]} },
    );
  my $base = $cfg->entry('paths', 'templates') 
    || $Constants::TMPLDIR;
  my $obj = Squirrel::Template->new(template_dir=>$base);
  return $obj->show_page($base, $template, \%acts);
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
  my $gen = Generate::Subscription->new(cfg=>$cfg);
  $gen->set_user($user);
  $gen->set_sub($sub);

  return $gen->generate(\%article, 'Articles');
}

sub send {
  my ($sub, $cfg, $opts, $callback) = @_;

  require 'SiteUsers.pm';
  my @recipients = SiteUsers->getSpecial('subRecipients', $sub->{id});
  $callback->(scalar(@recipients)." recipients to process");
  require 'BSE/Mail.pm';
  my $mailer = BSE::Mail->new(cfg=>$cfg);
  my %article;
  $sub->_build_article(\%article, $opts);
  my $gen;
  if ($article{template}) {
    print STDERR "Making generator\n";
    require 'Generate/Subscription.pm';
    $gen = Generate::Subscription->new(cfg=>$cfg);
    $gen->set_sub($sub);
  }
  my $from = $cfg->entryIfVar('subscriptions', 'from');
  unless ($from) {
    $from = $Constants::SHOP_FROM;
  }
  my $charset = $cfg->entry('basic', 'charset') || 'iso-8859-1';
  my $index = 0;
  for my $user (@recipients) {
    $callback->($user->{email}) if $callback;
    my $text = $sub->_text_format_low($cfg, $user, $opts, \%article);
    my $html;
    if ($gen && !$user->{textOnlyMail}) {
      print STDERR "Making HTML\n";
      $gen->set_user($user);
      $html = $gen->generate(\%article, 'Articles');
    }
    my @headers;
    my $content;
    push(@headers, "MIME-Version: 1.0");
    if ($html) {
      $html =~ tr/\cM/\cJ/;
      my $boundary = "====" . time . "=_=" .int(rand(10000))."=";
      push(@headers, qq!Content-Type: multipart/alternative; boundary="$boundary"!);
      $content = "This is a multi-part message in MIME format\n\n"
	. "--$boundary\n"
	  .qq!Content-Type: text/html; charset="$charset"\n\n!
	    . $html . "\n\n";
      $content .= "--$boundary\n"
	. qq!Content-Type: text/plain; charset="$charset"\n\n!
	  . $text . "\n\n";
      $content .= "--$boundary--\n";
    }
    else {
      push(@headers, qq!Content-Type: text/plain; charset="$charset"!);
      $content = $text;
      $content .= "\n" unless $content =~ /\n$/;
    }
    unless ($mailer->send(from	  =>$from, 
			  to	  =>$user->{email},
			  subject =>$article{title}, 
			  headers =>join("\n", @headers, ""),
			  body	  =>$content)) {
      $callback->("Error: ".$mailer->errstr);
    }
    ++$index;
  }
  if (exists $opts->{archive} && $opts->{archive}
      || $sub->{archive}) {
    $callback->("Archiving article");
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
    
    $callback->("Generating article");
    Util::generate_article('Articles', $article, $cfg);
  }
  use BSE::Util::SQL qw/now_datetime/;
  $sub->{lastSent} = now_datetime;
  $sub->save;
}

1;
