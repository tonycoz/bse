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

sub sub_form {
  my ($q, $session, $cfg, $template, $sub, $old, $errors) = @_;

  my %defs = ( archive => 1 );

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
     template =>
     sub {
       my ($name, $type, $optional) = split ' ', $_[0];

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
     },
     parent=>
     sub {
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
     },
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
    $subs{lastSent} = '0000-00-00 00:00';
    my $sub = BSE::SubscriptionTypes->add(@subs{@fields});
    
    _refresh_list();  
  }
  else {
    sub_form($q, $session, $cfg, 'admin/subs/add', undef, 1, \@errors);
  }
}

sub edit {
  my ($q, $session, $cfg) = @_;

  my $id = $q->param('id')
    or return _refresh_list("No id supplied to be edited");
  my $sub = BSE::SubscriptionTypes->getByPkey($id)
    or return _refresh_list("Cannot find record $id");
  sub_form($q, $session, $cfg, 'admin/subs/edit', $sub, 0);
}

sub editsave {
  my ($q, $session, $cfg) = @_;

  my $id = $q->param('id')
    or return _refresh_list("No id supplied to be edited");
  my $sub = BSE::SubscriptionTypes->getByPkey($id)
    or return _refresh_list("Cannot find record $id");

  my @errors;
  if (validate($q, $cfg, \@errors)) {
    my @fields = grep $_ ne 'id', BSE::SubscriptionType->columns;
    for my $field (@fields) {
      $sub->{$field} = $q->param($field) if defined $q->param($field);
    }
    $sub->save();
    _refresh_list();
  }
  else {
    sub_form($q, $session, $cfg, 'admin/subs/edit', $sub, 1, \@errors);
  }
}

sub start_send {
  my ($q, $session, $cfg) = @_;

  my $msgs = BSE::Message->new(cfg=>$cfg, section=>'subs');
  my $id = $q->param('id')
    or return _refresh_list($msgs->(startnoid=>"No id supplied to be edited"));
  my $sub = BSE::SubscriptionTypes->getByPkey($id)
    or return _refresh_list($msgs->(startnosub=>"Cannot find record $id"));
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
    or return _refresh_list($msgs->(startnoid=>"No id supplied to be edited"));
  my $sub = BSE::SubscriptionTypes->getByPkey($id)
    or return _refresh_list($msgs->(startnosub=>"Cannot find record $id"));
  my %acts;
  %acts =
    (
     BSE::Util::Tags->basic(\%acts, $q, $cfg),
     BSE::Util::Tags->admin(\%acts, $cfg),
     sub => sub { CGI::escapeHTML($sub->{$_[0]}) },
     message => sub { '' },
     ifError => sub { 0 },
     old => sub { CGI::escapeHTML(defined $sub->{$_[0]} ? $sub->{$_[0]} : '') },
    );
  BSE::Template->show_page('admin/subs/send_form', $cfg, \%acts);
}

sub html_preview {
  my ($q, $session, $cfg) = @_;

  print "Content-Type: text/html\n\n<html></html>\n";
}
