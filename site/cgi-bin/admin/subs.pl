#!/usr/bin/perl -w
use strict;
use FindBin;
use lib "$FindBin::Bin/../modules";
use BSE::SubscriptionTypes;
use CGI;
use BSE::DB;
use BSE::Cfg;
use BSE::Session;
use BSE::Util::Tags;
use BSE::Template;
use Constants qw($TMPLDIR);
use Articles;
use Util qw/refresh_to/;
use BSE::Message;

my $cfg = BSE::Cfg->new;
my %session;
BSE::Session->tie_it(\%session, $cfg);

my %steps =
  (
   list => \&list,
   add => \&add,
   addsave => \&addsave,
   edit => \&edit,
   editsave => \&editsave,
   start_send => \&start_send,
   send_form => \&send_form,
   html_preview => \&html_preview,
   text_preview => \&text_preview,
   send => \&send_message,
  );

my $q = CGI->new;
my $action = 'list';
for my $name (keys %steps) {
  if ($q->param($name)) {
    $action = $name;
    last;
  }
}

$steps{$action}->($q, \%session, $cfg);

untie %session;

sub list {
  my ($q, $session, $cfg) = @_;

  my $message = $q->param('m') || '';
  my @subs = sort { lc $a->{name} cmp $b->{name} } BSE::SubscriptionTypes->all;
  my $subindex;
  my %acts;
  %acts =
    (
     BSE::Util::Tags->basic(\%acts, $q, $cfg),
     BSE::Util::Tags->make_iterator(\@subs, 'subscription', 'subscriptions',
				    \$subindex),
     message => sub { CGI::escapeHTML($message) },
    );
  BSE::Template->show_page('admin/subs/list', $cfg, \%acts);
}

sub _template_popup {
  my ($cfg, $q, $sub, $old, $args) = @_;

  my ($name, $type, $optional) = split ' ', $args;
  
  my @templates;
  my $base = 'common';
  if ($type) {
    $base = $cfg->entry('subscriptions', "${type}_templates")
      || $type;
  }
  if (opendir TEMPL, "$TMPLDIR/$base") {
    push(@templates, sort map "$base/$_",
	 grep -f "$TMPLDIR/$base/$_" && /\.tmpl$/i, readdir TEMPL);
    closedir TEMPL;
    @templates or push(@templates, "Could not find templates in $base");
  }
  else {
    push(@templates, "Cannot open dir $TMPLDIR/$base");
  }
  my $def = $old ? $q->param($name) :
    $sub ? $sub->{$name} : $templates[0];
  my %labels;
  @labels{@templates} = @templates;
  if ($optional) {
    unshift(@templates, '');
    $labels{''} = "(no HTML part)";
  }
  return CGI::popup_menu(-name=>$name, -values=>\@templates,
			 -labels=>\%labels,
			 -default=>$def, -override=>1);
}

sub _parent_popup {
  my ($sub, $old) = @_;

  my @all = Articles->summary();
  my %labels = map { $_->{id}, "$_->{title} ($_->{id})" } @all;
  my @extras;
  if ($sub && !$old) {
    @extras = ( -default=>$sub->{parentId} );
  }
  return CGI::popup_menu(-name=>'parentId',
			 -values=> [ map $_->{id}, @all ],
			 -labels => \%labels,
			 @extras);
}

sub sub_form {
  my ($q, $session, $cfg, $template, $sub, $old, $errors) = @_;

  my %defs = ( archive => 1, visible => 1 );

  my $message = '';
  $errors ||= [];
  $message = join("<br>\n", map CGI::escapeHTML($_->[1]), @$errors)
    if @$errors;
  my %errors;
  for my $error (@$errors) {
    push(@{$errors{$error->[0]}}, $error->[1]);
  }
  my %acts;
  %acts =
    (
     BSE::Util::Tags->basic(\%acts, $q, $cfg),
     BSE::Util::Tags->admin(\%acts, $cfg),
     old =>
     sub {
       CGI::escapeHTML($old ? $q->param($_[0]) :
                       $sub ? $sub->{$_[0]} : 
		       $defs{$_[0]} || '');
     },
     message => sub { $message },
     template => sub { return _template_popup($cfg, $q, $sub, $old, $_[0]) },
     parent=> sub { _parent_popup($sub, $old)  },
     error =>
     sub {
       my ($name, $sep) = split ' ', $_[0], 2;
       if (my $msgs = $errors{$_[0]}) {
	 $sep ||= ',';
	 return join($sep, map CGI::escapeHTML($_), @$msgs);
       }
       else {
	 return '';
       }
     },
    );
  if ($sub) {
    $acts{subscription} =
      sub {
	CGI::escapeHTML($sub->{$_[0]});
      };
  }

  BSE::Template->show_page($template, $cfg, \%acts);
}

sub add {
  my ($q, $session, $cfg) = @_;

  sub_form($q, $session, $cfg, 'admin/subs/add', undef, 0);
}

sub validate {
  my ($q, $cfg, $errors) = @_;

  my @needed = qw(name title description frequency text_template);
  push(@needed, qw/article_template parentId/) if $q->param('archive');
  for my $field (@needed) {
    my $value = $q->param($field);
    defined $value and length $value
      or push(@$errors, [ $field, "$field must be entered" ]);
  }
  for my $field (qw(html_template text_template article_template)) {
    my $value = $q->param($field);
    if ($value) {
      if ($value =~ /\.\./) {
	push(@$errors, [ $field, "Template $value is invalid, contains .." ]);
      }
      elsif (!-f "$TMPLDIR/$value") {
	push(@$errors, [ $field, "Template $value does not exist" ]);
      }
    }
  }
  if ($q->param('archive')) {
    my $id = $q->param('parentId');
    if ($id) {
      my $article = Articles->getByPkey($id)
	or push(@$errors, [ 'parentId', "Select a parent for the archive" ]);
    }
  }

  return !@$errors;
}

sub _refresh_list {
  my ($cfg, $msg) = @_;

  my $url = $cfg->entryErr('site', 'url') . "/cgi-bin/admin/subs.pl";
  if ($msg) {
    $url .= "m=" . CGI::escape($msg);
  }
  refresh_to($url);
}

sub addsave {
  my ($q, $session, $cfg) = @_;

  my @errors;
  if (validate($q, $cfg, \@errors)) {
    my %subs;
    my @fields = grep $_ ne 'id', BSE::SubscriptionType->columns;
    for my $field (@fields) {
      $subs{$field} = $q->param($field) if defined $q->param($field);
    }
    $subs{archive} = () = $q->param('archive');
    $subs{visible} = 0 + defined $q->param('visible');
    $subs{lastSent} = '0000-00-00 00:00';
    my $sub = BSE::SubscriptionTypes->add(@subs{@fields});
    
    _refresh_list($cfg);  
  }
  else {
    sub_form($q, $session, $cfg, 'admin/subs/add', undef, 1, \@errors);
  }
}

sub edit {
  my ($q, $session, $cfg) = @_;

  my $id = $q->param('id')
    or return _refresh_list($cfg, "No id supplied to be edited");
  my $sub = BSE::SubscriptionTypes->getByPkey($id)
    or return _refresh_list($cfg, "Cannot find record $id");
  sub_form($q, $session, $cfg, 'admin/subs/edit', $sub, 0);
}

sub editsave {
  my ($q, $session, $cfg) = @_;

  my $id = $q->param('id')
    or return _refresh_list($cfg, "No id supplied to be edited");
  my $sub = BSE::SubscriptionTypes->getByPkey($id)
    or return _refresh_list($cfg, "Cannot find record $id");

  my @errors;
  if (validate($q, $cfg, \@errors)) {
    my @fields = grep $_ ne 'id', BSE::SubscriptionType->columns;
    for my $field (@fields) {
      $sub->{$field} = $q->param($field) if defined $q->param($field);
    }
    $sub->{archive} = () = $q->param('archive');
    $sub->{visible} = 0 + defined $q->param('visible');
    $sub->save();
    _refresh_list($cfg);
  }
  else {
    sub_form($q, $session, $cfg, 'admin/subs/edit', $sub, 1, \@errors);
  }
}

sub start_send {
  my ($q, $session, $cfg) = @_;

  my $msgs = BSE::Message->new(cfg=>$cfg, section=>'subs');
  my $id = $q->param('id')
    or return _refresh_list($cfg, $msgs->(startnoid=>"No id supplied to be edited"));
  my $sub = BSE::SubscriptionTypes->getByPkey($id)
    or return _refresh_list($cfg, $msgs->(startnosub=>"Cannot find record $id"));
  my %acts;
  %acts =
    (
     BSE::Util::Tags->basic(\%acts, $q, $cfg),
     sub => sub { CGI::escapeHTML($sub->{$_[0]}) },
    );
  BSE::Template->show_page('admin/subs/start_send', $cfg, \%acts);
}

sub send_form {
  my ($q, $session, $cfg) = @_;

  my $msgs = BSE::Message->new(cfg=>$cfg, section=>'subs');
  my $id = $q->param('id')
    or return _refresh_list($cfg, $msgs->(startnoid=>"No id supplied to be edited"));
  my $sub = BSE::SubscriptionTypes->getByPkey($id)
    or return _refresh_list($cfg, $msgs->(startnosub=>"Cannot find record $id"));
  my %acts;
  %acts =
    (
     BSE::Util::Tags->basic(\%acts, $q, $cfg),
     BSE::Util::Tags->admin(\%acts, $cfg),
     subscription => sub { CGI::escapeHTML($sub->{$_[0]}) },
     message => sub { '' },
     ifError => sub { 0 },
     old => sub { CGI::escapeHTML(defined $sub->{$_[0]} ? $sub->{$_[0]} : '') },
     template => sub { return _template_popup($cfg, $q, $sub, 0, $_[0]) },
     parent=> sub { _parent_popup($sub, {})  },
    );
  BSE::Template->show_page('admin/subs/send_form', $cfg, \%acts);
}

sub html_preview {
  my ($q, $session, $cfg) = @_;

  my $msgs = BSE::Message->new(cfg=>$cfg, section=>'subs');
  my $id = $q->param('id')
    or return _refresh_list($cfg, $msgs->(startnoid=>"No id supplied to be edited"));
  my $sub = BSE::SubscriptionTypes->getByPkey($id)
    or return _refresh_list($cfg, $msgs->(startnosub=>"Cannot find record $id"));
  my %opts;
  for my $key ($q->param()) {
    # I'm not worried about multiple items
    $opts{$key} = ($q->param($key))[0];
  }
  my $template = $q->param('html_template');
  $template = $sub->{html_template} unless defined $template;
  if ($template) {
    # build a fake article
    my $text = $sub->html_format($cfg, _dummy_user(), \%opts);
    print "Content-Type: text/html\n\n";
    print $text;
  }
  else {
    print <<EOS;
Content-Type: text/html

You have no HTML template selected.
EOS
  }
}

#  sub _text_format {
#    my ($cfg, $article, $user, $template) = @_;

#    my %acts;
#    %acts =
#      (
#       article=>sub { $article->{$_[0]} },
#       ifUser => sub { $user },
#       user =>
#       sub {
#         $user or return '';
#         defined $user->{$_[0]} or return '';
#         $user->{$_[0]}
#       },
#       body =>
#       sub {
#         _format_body($cfg, $article->{body});
#       },
#      );
#    my $base = $cfg->entry('paths', 'templates') 
#      || $TMPLDIR;
#    my $obj = Squirrel::Template->new(template_dir=>$base);
#    return $obj->show_page($base, $template, \%acts);
#  }

sub _dummy_user {
  my %user;
  $user{id} = 0;
  $user{userId} = "demo";
  $user{email} = 'someone@somewhere.com';
  $user{name1} = "Some";
  $user{name2} = "One";
  $user{confirmSecret} = "X" x 32;

  \%user;
}

sub text_preview {
  my ($q, $session, $cfg) = @_;

  my $msgs = BSE::Message->new(cfg=>$cfg, section=>'subs');
  my $id = $q->param('id')
    or return _refresh_list($cfg, $msgs->(startnoid=>"No id supplied to be edited"));
  my $sub = BSE::SubscriptionTypes->getByPkey($id)
    or return _refresh_list($cfg, $msgs->(startnosub=>"Cannot find record $id"));

  my %opts;
  for my $key ($q->param()) {
    # I'm not worried about multiple items
    $opts{$key} = ($q->param($key))[0];
  }
  my $text = $sub->text_format($cfg, _dummy_user(), \%opts);
  if ($ENV{HTTP_USER_AGENT} =~ /MSIE/) {
    # IE is so broken
    print "Content-Type: text/html\n\n";
    print "<html><body><pre>",CGI::escapeHTML($text),"</pre></body></html>";
  }
  else {
    print "Content-Type: text/plain\n\n";
    print $text;
  }
}

sub _first {
  for (@_) {
    return $_ if defined;
  }
  undef;
}

sub send_message {
  my ($q, $session, $cfg) = @_;

  my $msgs = BSE::Message->new(cfg=>$cfg, section=>'subs');
  my $id = $q->param('id')
    or return _refresh_list($cfg, $msgs->(startnoid=>"No id supplied to be edited"));
  my $sub = BSE::SubscriptionTypes->getByPkey($id)
    or return _refresh_list($cfg, $msgs->(startnosub=>"Cannot find record $id"));

  my %opts;
  for my $key ($q->param()) {
    # I'm not worried about multiple items
    $opts{$key} = ($q->param($key))[0];
  }
  if ($q->param('have_archive_check')) {
    $opts{archive} = defined $q->param('archive')
  }

  print "Content-Type: text/html\n\n";
  print "<html><head><title>Send Subscription - BSE</title></head>";
  print "<body><h2>Send Subscription</h2>\n";
  $sub->send($cfg, \%opts,
	     sub {
	       print "<div>",CGI::escapeHTML($_[0]),"</div>\n";
	     });
  print qq!<p><a target="_top" href="/admin/">Back to Admin Menu</a></p>\n!;
  print "</body></html>\n";
}
