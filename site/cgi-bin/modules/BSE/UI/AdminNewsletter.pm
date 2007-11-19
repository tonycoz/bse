package BSE::UI::AdminNewsletter;
use strict;
use BSE::SubscriptionTypes;
use BSE::Util::Tags qw(tag_hash);
use Articles;
use BSE::Message;
use DevHelp::HTML qw(:default popup_menu);
use BSE::Util::Iterate;
use base 'BSE::UI::AdminDispatch';

my %actions =
  (
   list => '',
   add => 'subs_add',
   addsave => 'subs_add',
   edit => 'subs_edit',
   editsave => 'subs_edit',
   start_send => 'subs_send',
   send_form => 'subs_send',
   html_preview => 'subs_send',
   text_preview => 'subs_send',
   filter_preview => 'subs_send',
   send => 'subs_send',
   send_test => 'subs_send',
   delconfirm => 'subs_delete',
   delete => 'subs_delete',
  );

sub actions {
  \%actions;
}

sub rights {
  \%actions;
}

sub default_action {
  'list';
}

sub action_prefix {
  ''
}

sub tag_list_recipient_count {
  my ($subs, $subindex) = @_;

  $$subindex >= 0 && $$subindex < @$subs
    or return '** subscriber_count only valid inside subscriptions iterator **';

  $subs->[$$subindex]->recipient_count;
}

sub req_list {
  my ($class, $req, $message) = @_;

  my $q = $req->cgi;
  my $cfg = $req->cfg;
  $message ||= $q->param('m') || '';
  my @subs = sort { lc $a->{name} cmp $b->{name} } BSE::SubscriptionTypes->all;
  my $subindex;
  my %acts;
  %acts =
    (
     BSE::Util::Tags->basic(\%acts, $q, $cfg),
     BSE::Util::Tags->make_iterator(\@subs, 'subscription', 'subscriptions',
				    \$subindex),
     BSE::Util::Tags->secure($req),
     BSE::Util::Tags->admin(\%acts, $cfg),
     message => escape_html($message),
     recipient_count => [ \&tag_list_recipient_count, \@subs, \$subindex ],
    );

  return $req->dyn_response('admin/subs/list', \%acts);
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
  for my $dir (BSE::Template->template_dirs($cfg)) {
    if (opendir TEMPL, "$dir/$base") {
      push(@templates, sort map "$base/$_",
	   grep -f "$dir/$base/$_" && /\.tmpl$/i, readdir TEMPL);
      closedir TEMPL;
    }
  }
  my %seen_templates;
  @templates = sort grep !$seen_templates{$_}++, @templates;
  @templates or push(@templates, "Could not find templates in $base");
  my $def = $old ? $q->param($name) :
    $sub ? $sub->{$name} : $templates[0];
  my %labels;
  @labels{@templates} = @templates;
  if ($optional) {
    unshift(@templates, '');
    $labels{''} = "(no HTML part)";
  }
  return popup_menu(-name=>$name, 
		    -values=>\@templates,
		    -labels=>\%labels,
		    -default=>$def);
}

sub _valid_archive_types {
  my ($req) = @_;

  my %valid;
  my %types = $req->cfg->entriesCS('valid child types');
  for my $type (keys %types) {
    for my $child (split /,/, $types{$type}) {
      if ($child eq 'Article') {
	$valid{$type} = 1;
	last;
      }
    }
  }

  return keys %valid;
}

sub _parent_popup {
  my ($req, $sub, $old) = @_;

  my %valid_types = map { $_ => 1 } _valid_archive_types($req);
  my $shopid = $req->cfg->entryErr('articles', 'shop');
  my @all = Articles->query([qw/id title generator/],
			   [ [ '<>', 'id', $shopid ] ]);
  if ($req->cfg->entry('basic', 'access_filter_parents', 0)) {
    @all = grep($req->user_can('edit_add_child', $_->{id})
		|| ($sub && $sub->{parentId} == $_->{id}),
		 @all);
  }
  @all = 
    grep 
    {
      my $type = ($_->{generator} =~ /(\w+)$/)[0] || 'Article';

      $valid_types{$type} && $_->{id} != $shopid
    } @all;
  my %labels = map { $_->{id}, "$_->{title} ($_->{id})" } @all;
  @all = sort { lc $labels{$a->{id}} cmp lc $labels{$b->{id}} } @all;
  my @extras;
  unless ($old) {
    if ($sub) {
      @extras = ( -default=>$sub->{parentId} );
    }
    else {
      # use the highest id, presuming the most recent article created
      # was created to store subscriptions
      my $max = -1;
      $max < $_->{id} and $max = $_->{id} for @all;
      @extras = ( -default=>$max );
    }
  }
  return popup_menu(-name=>'parentId',
		    -values=> [ map $_->{id}, @all ],
		    -labels => \%labels,
		    @extras);
}

sub sub_form {
  my ($req, $template, $sub, $old, $errors) = @_;

  my $q = $req->cgi;
  my $cfg = $req->cfg;
  my %defs = ( archive => 1, visible => 1 );

  my $message = '';
  $errors ||= [];
  $message = join("<br>\n", map escape_html($_->[1]), @$errors)
    if @$errors;
  my %errors;
  for my $error (@$errors) {
    push(@{$errors{$error->[0]}}, $error->[1]);
  }
  unless ($message) {
    $message = $q->param('m');
    defined $message or $message = '';
    $message = escape_html($message);
  }
  my %acts;
  %acts =
    (
     BSE::Util::Tags->basic(\%acts, $q, $cfg),
     BSE::Util::Tags->admin(\%acts, $cfg),
     old =>
     sub {
       escape_html($old ? $q->param($_[0]) :
		   $sub ? $sub->{$_[0]} : 
		   $defs{$_[0]} || '');
     },
     message => sub { $message },
     template => sub { return _template_popup($cfg, $q, $sub, $old, $_[0]) },
     parent=> sub { _parent_popup($req, $sub, $old)  },
     error =>
     sub {
       my ($name, $sep) = split ' ', $_[0], 2;
       if (my $msgs = $errors{$_[0]}) {
	 $sep ||= ',';
	 return join($sep, map escape_html($_), @$msgs);
       }
       else {
	 return '';
       }
     },
     ifNew => !defined($sub),
    );
  if ($sub) {
    $acts{subscription} = [ \&tag_hash, $sub ];
  }

  return $req->dyn_response($template, \%acts);
}

sub req_add {
  my ($class, $req) = @_;

  return sub_form($req, 'admin/subs/edit', undef, 0);
}

sub validate {
  my ($req, $q, $cfg, $errors, $sub) = @_;

  my @needed = qw(name title description frequency text_template);
  push(@needed, qw/article_template parentId/) if $q->param('archive');
  for my $field (@needed) {
    my $value = $q->param($field);
    defined $value and length $value
      or push(@$errors, [ $field, "\u$field must be entered" ]);
  }
  for my $field (qw(html_template text_template article_template)) {
    my $value = $q->param($field);
    if ($value) {
      if ($value =~ /\.\./) {
	push(@$errors, [ $field, "Template $value is invalid, contains .." ]);
      }
      elsif (!BSE::Template->find_source($value, $cfg)) {
	push(@$errors, [ $field, "Template $value does not exist" ]);
      }
    }
  }
  if ($q->param('archive')) {
    my $id = $q->param('parentId');
    if ($id) {
      my $article = Articles->getByPkey($id);
      if ($article) {
	unless ($req->user_can('edit_add_child', $article)
		|| ($sub && $sub->{parentId} == $id)) {
	  push @$errors, [ parentId => "You don't have permission to add children to that article" ];
	}
      }
      else {
	push(@$errors, [ 'parentId', "Select a parent for the archive" ]);
      }
    }
  }

  return !@$errors;
}

sub _refresh_list {
  my ($req, $msg) = @_;

  my $url = $req->cgi->param('r');
  unless ($url) {
    $url = "/cgi-bin/admin/subs.pl";
    if ($msg) {
      $url .= "?m=" . escape_uri($msg);
    }
  }

  return BSE::Template->get_refresh($url, $req->cfg);
}

sub req_addsave {
  my ($class, $req) = @_;

  my $q = $req->cgi;
  my $cfg = $req->cfg;
  my @errors;
  if (validate($req, $q, $cfg, \@errors)) {
    my %subs;
    my @fields = grep $_ ne 'id', BSE::SubscriptionType->columns;
    for my $field (@fields) {
      $subs{$field} = $q->param($field) if defined $q->param($field);
    }
    $subs{archive} = () = $q->param('archive');
    $subs{visible} = 0 + defined $q->param('visible');
    $subs{lastSent} = '0000-00-00 00:00';
    my $sub = BSE::SubscriptionTypes->add(@subs{@fields});
    
    return _refresh_list($req, "Subscription created");  
  }
  else {
    return sub_form($req, 'admin/subs/edit', undef, 1, \@errors);
  }
}

sub req_edit {
  my ($class, $req) = @_;

  my $id = $req->cgi->param('id')
    or return _refresh_list($req, "No id supplied to be edited");

  my $sub = BSE::SubscriptionTypes->getByPkey($id)
    or return _refresh_list($req, "Cannot find record $id");

  return sub_form($req, 'admin/subs/edit', $sub, 0);
}

sub req_editsave {
  my ($class, $req) = @_;

  my $q = $req->cgi;
  my $cfg = $req->cfg;

  my $id = $q->param('id')
    or return _refresh_list($req, "No id supplied to be edited");
  my $sub = BSE::SubscriptionTypes->getByPkey($id)
    or return _refresh_list($req, "Cannot find record $id");

  my @errors;
  if (validate($req, $q, $cfg, \@errors, $sub)) {
    my @fields = grep $_ ne 'id', BSE::SubscriptionType->columns;
    for my $field (@fields) {
      $sub->{$field} = $q->param($field) if defined $q->param($field);
    }
    $sub->{archive} = () = $q->param('archive');
    $sub->{visible} = 0 + defined $q->param('visible');
    $sub->save();
    return _refresh_list($req, "Subscription saved");
  }
  else {
    return sub_form($req, 'admin/subs/edit', $sub, 1, \@errors);
  }
}

sub req_start_send {
  my ($class, $req) = @_;

  my $cfg = $req->cfg;
  my $q = $req->cgi;

  my $msgs = BSE::Message->new(cfg=>$cfg, section=>'subs');
  my $id = $q->param('id')
    or return _refresh_list($req, $msgs->(startnoid=>"No id supplied to be edited"));
  my $sub = BSE::SubscriptionTypes->getByPkey($id)
    or return _refresh_list($req, $msgs->(startnosub=>"Cannot find record $id"));
  my %acts;
  %acts =
    (
     BSE::Util::Tags->basic(\%acts, $q, $cfg),
     sub => [ \&tag_hash, $sub ],
    );

  return $req->dyn_response('admin/subs/start_send', \%acts);
}

sub tag_recipient_count {
  my ($sub, $rcount_cache) = @_;

  defined $$rcount_cache or $$rcount_cache = $sub->recipient_count;

  $$rcount_cache;
}

sub req_send_form {
  my ($class, $req) = @_;

  my $cfg = $req->cfg;
  my $q = $req->cgi;

  my @filters = BSE::SubscriptionTypes->filters($cfg);

  my $msgs = BSE::Message->new(cfg=>$cfg, section=>'subs');
  my $id = $q->param('id')
    or return _refresh_list($req, $msgs->(startnoid=>"No id supplied to be edited"));
  my $sub = BSE::SubscriptionTypes->getByPkey($id)
    or return _refresh_list($req, $msgs->(startnosub=>"Cannot find record $id"));
  my $count_cache;
  my %acts;
  %acts =
    (
     BSE::Util::Tags->basic(\%acts, $q, $cfg),
     BSE::Util::Tags->admin(\%acts, $cfg),
     subscription => [ \&tag_hash, $sub ],
     message => sub { '' },
     ifError => sub { 0 },
     old => sub { escape_html(defined $sub->{$_[0]} ? $sub->{$_[0]} : '') },
     template => sub { return _template_popup($cfg, $q, $sub, 0, $_[0]) },
     parent=> sub { _parent_popup($req, $sub)  },
     recipient_count => [ \&tag_recipient_count, $sub, \$count_cache ],
     map($_->tags, @filters),
     ifFilters => scalar(@filters),
    );

  return $req->dyn_response('admin/subs/send_form', \%acts);
}

sub req_html_preview {
  my ($class, $req) = @_;

  my $cfg = $req->cfg;
  my $q = $req->cgi;

  my $msgs = BSE::Message->new(cfg=>$cfg, section=>'subs');
  my $id = $q->param('id')
    or return _refresh_list($req, $msgs->(startnoid=>"No id supplied to be edited"));
  my $sub = BSE::SubscriptionTypes->getByPkey($id)
    or return _refresh_list($req, $msgs->(startnosub=>"Cannot find record $id"));
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
    return
      {
       type => 'text/html',
       content => $text,
      };
  }
  else {
    return
      {
       type => 'text/html',
       content => 'You have no HTML template selected.',
      };
  }
}

sub _dummy_user {
  my %user;
  $user{id} = 0;
  $user{userId} = "username";
  $user{password} = "p455w0rd";
  $user{email} = 'dummy@example.com';
  $user{name1} = "Firstname";
  $user{name2} = "Lastname";
  $user{confirmSecret} = "X" x 32;
  
  \%user;
}

sub req_text_preview {
  my ($class, $req) = @_;

  my $cfg = $req->cfg;
  my $q = $req->cgi;

  my $msgs = BSE::Message->new(cfg=>$cfg, section=>'subs');
  my $id = $q->param('id')
    or return _refresh_list($req, $msgs->(startnoid=>"No id supplied to be edited"));
  my $sub = BSE::SubscriptionTypes->getByPkey($id)
    or return _refresh_list($req, $msgs->(startnosub=>"Cannot find record $id"));

  my %opts;
  for my $key ($q->param()) {
    # I'm not worried about multiple items
    $opts{$key} = ($q->param($key))[0];
  }
  my $text = $sub->text_format($cfg, _dummy_user(), \%opts);
  
  if ($ENV{HTTP_USER_AGENT} =~ /MSIE/) {
    return
      {
       type => 'text/html',
       content => "<html><body><pre>".escape_html($text)."</pre></body></html>"
      };
  }
  else {
    return
      {
       type => 'text/plain',
       content => $text,
      };
  }
}

sub req_filter_preview {
  my ($class, $req) = @_;

  my $cfg = $req->cfg;
  my $q = $req->cgi;

  my $msgs = BSE::Message->new(cfg=>$cfg, section=>'subs');
  my $id = $q->param('id')
    or return _refresh_list($req, $msgs->(startnoid=>"No id supplied to be edited"));

  my $sub = BSE::SubscriptionTypes->getByPkey($id)
    or return _refresh_list($req, $msgs->(startnosub=>"Cannot find record $id"));

  my @filters = BSE::SubscriptionTypes->filters($cfg);
  my @all_subscribers = $sub->recipients;
  my @filter_res;
  my @subscribers = @all_subscribers;

  my $index = 1;
  for my $filter (@filters) {
    if ($q->param("criteria$index")) {
      my @members = $filter->members($q);
      my %members = map { $_ => 1 } @members;
      @subscribers = grep $members{$_->{id}}, @subscribers;
      # not much to say at this point
      push @filter_res,
	{
	 enabled => 1,
	 filter_count => scalar(@members),
	 subscriber_count => scalar(@subscribers),
	};
    }
    else {
      push @filter_res,
	{
	 enabled => 0,
	 filter_count => 0,
	 subcriber_count => scalar(@subscribers),
	};
    }
    ++$index;
  }

  my $it = BSE::Util::Iterate->new;
  my %acts;
  %acts =
    (
     BSE::Util::Tags->basic(\%acts, $q, $cfg),
     BSE::Util::Tags->admin(\%acts, $cfg),
     subscription => [ \&tag_hash, $sub ],
     (map {;
       "filter$_" => [ \&tag_hash, $filter_res[$_-1] ],
     } 1..@filters),
     $it->make_iterator(undef, 'filter', 'filters', \@filter_res),
     total_count => scalar(@all_subscribers),
     filter_count => scalar(@subscribers),
    );

  return $req->dyn_response('admin/subs/filter_preview', \%acts);
}

sub _first {
  for (@_) {
    return $_ if defined;
  }
  undef;
}

sub _send_errors {
  my ($req, $sub, $errors) = @_;

  my @errors = map +{ field=> $_, message => $errors->{$_} }, keys %$errors;
  my %acts;
  %acts =
    (
     BSE::Util::Tags->basic(\%acts, $req->cgi, $req->cfg),
     BSE::Util::Tags->admin(\%acts, $req->cfg),
     subscription => [ \&tag_hash, $sub ],
     BSE::Util::Tags->make_iterator(\@errors, 'error', 'errors'),
    );
  
  return $req->dyn_response('admin/subs/send_error', \%acts);
}

sub _send_setup {
  my ($req, $opts, $rsub, $rresult) = @_;

  my $q = $req->cgi;
  my $cfg = $req->cfg;

  my $msgs = BSE::Message->new(cfg=>$cfg, section=>'subs');
  my $id = $req->cgi->param('id');
  unless ($id) {
    $$rresult = _refresh_list($req, $msgs->(startnoid=>"No id supplied to be sent"));
    return;
  }
  my $sub = BSE::SubscriptionTypes->getByPkey($id);
  unless ($sub) {
    $$rresult = _refresh_list($req, $msgs->(startnosub=>"Cannot find record $id"));
    return;
  }

  my %errors;
  for my $key ($q->param()) {
    # I'm not worried about multiple items
    $opts->{$key} = ($q->param($key))[0];
  }
  if ($q->param('have_archive_check')) {
    $opts->{archive} = defined $q->param('archive')
  }
  # work our way through, so we have a consistent set of data to validate
  for my $key (grep $_ ne 'id', BSE::SubscriptionType->columns) {
    unless (exists $opts->{$key}) {
      $opts->{$key} = $sub->{$key};
    }
  }
  if ($opts->{archive} &&
      ($opts->{parentId} && $opts->{parentId} != $sub->{parentId})) {
    $req->user_can('edit_add_child', $opts->{parentId})
      or $errors{parentId} = "You cannot add children to the archive parent";
  }
  $opts->{title} eq ''
    and $errors{title} = "Please enter a title";
  $opts->{body} eq ''
    and $errors{body} = "Please enter a body";

  if (keys %errors) {
    $$rresult = _send_errors($req, $sub, \%errors);
    return;
  }
  
  $$rsub = $sub;

  return 1;
}

sub req_send_test {
  my ($class, $req) = @_;

  my %opts;
  my $sub;
  my $result;
  _send_setup($req, \%opts, \$sub, \$result)
    or return $result;

  my $cfg = $req->cfg;
  my $q = $req->cgi;

  $cfg->entry('subscriptions', 'testing', 1)
    or return _send_errors($req, $sub, 
			   { error => "Test subscription messages disabled" });

  # make sure the user is being authenticated in some way
  # this prevents spammers from using this to send their messages
  $ENV{REMOTE_USER} || $req->getuser
    or return _send_errors($req, $sub, 
			   { error => "You must be authenticated to use this function.  Either enable access control or setup .htpasswd." });

  my $testemail = $q->param('testemail');
  my $testname = $q->param('testname');
  my $testtextonly = $q->param('testtextonly');

  require SiteUsers;
  my %recipient = 
    (
     (map { $_ => '' } SiteUser->columns),
     id => 999,
     userId => 'username',
     password => 'p455w0rd',
     email => $testemail,
     name1 => $testname,
     name2 => 'Lastname',
     confirmSecret => 'TESTTESTTESTTESTTESTTESTTESTTEST',
     textOnlyMail => (defined $testtextonly ? 1 : 0 ),
    );

  my %errors;
  unless ($testemail && $testemail =~ /.\@./) {
    $errors{testemail} = "Please enter a test email address to send a test";
  }
  unless ($testname) {
    $errors{testname} = "Please enter a test name to send a test";
  }
  keys %errors
    and return _send_errors($req, $sub, \%errors);

  my $template = BSE::Template->get_source('admin/subs/sending', $cfg);

  my ($prefix, $permessage, $suffix) = 
    split /<:\s*iterator\s+(?:begin|end)\s+messages\s*:>/, $template;
  my $acts_message;
  my $acts_user;
  my $is_error;
  my %acts;
  %acts =
    (
     BSE::Util::Tags->basic(\%acts, $q, $cfg),
     BSE::Util::Tags->admin(\%acts, $cfg),
     subscription => [ \&tag_hash, $sub ],
     message => sub { $acts_message },
     user => sub { $acts_user ? escape_html($acts_user->{$_[0]}) : '' },
     ifUser => sub { $acts_user },
     ifError => sub { $is_error },
     testing => 1,
    );
  BSE::Template->show_replaced($prefix, $cfg, \%acts);
  $sub->send_test($cfg, \%opts,
		  sub {
		    my ($type, $user, $msg) = @_;
		    $acts_message = defined($msg) ? $msg : '';
		    $acts_user = $user;
		    $is_error = $type eq 'error';
		    print BSE::Template->replace($permessage, $cfg, \%acts);
		  },
		 \%recipient);
  print BSE::Template->replace($suffix, $cfg, \%acts);
  return;
}

sub _get_filtered_ids {
  my ($req) = @_;

  my @filters = BSE::SubscriptionTypes->filters($req->cfg);

  my $cgi = $req->cgi;

  # only want the enabled filters
  my @active;
  my $index = 1;
  for my $filter (@filters) {
    push @active, $filter
      if $cgi->param("criteria$index");
    ++$index;
  }
  @active
    or return;

  my $first = shift @active;
  my @ids = $first->members($req->cgi);
  for my $filter (@active) {
    my %members = map { $_=>1 } $filter->members($req->cgi);
    @ids = grep $members{$_}, @ids;
  }

  \@ids;
}

sub req_send {
  my ($class, $req) = @_;

  my %opts;
  my $sub;
  my $result;
  _send_setup($req, \%opts, \$sub, \$result)
    or return $result;

  my $q = $req->cgi;
  my $cfg = $req->cfg;

  my $filtered_ids = _get_filtered_ids($req);

  my $template = BSE::Template->get_source('admin/subs/sending', $cfg);

  my ($prefix, $permessage, $suffix) = 
    split /<:\s*iterator\s+(?:begin|end)\s+messages\s*:>/, $template;
  my $acts_message;
  my $acts_user;
  my $is_error;
  my %acts;
  %acts =
    (
     BSE::Util::Tags->basic(\%acts, $q, $cfg),
     BSE::Util::Tags->admin(\%acts, $cfg),
     subscription => [ \&tag_hash, $sub ],
     message => sub { $acts_message },
     user => sub { $acts_user ? escape_html($acts_user->{$_[0]}) : '' },
     ifUser => sub { $acts_user },
     ifError => sub { $is_error },
     testing => 0,
    );
  BSE::Template->show_replaced($prefix, $cfg, \%acts);
  $sub->send($cfg, \%opts,
	     sub {
	       my ($type, $user, $msg) = @_;
	       $acts_message = defined($msg) ? $msg : '';
	       $acts_user = $user;
	       $is_error = $type eq 'error';
	       print BSE::Template->replace($permessage, $cfg, \%acts);
	     }, $filtered_ids);
  print BSE::Template->replace($suffix, $cfg, \%acts);

  return;
}

sub req_delconfirm {
  my ($class, $req) = @_;

  my $cfg = $req->cfg;
  my $q = $req->cgi;

  my $id = $q->param('id')
    or return _refresh_list($req, "No id supplied to be deleted");

  my $sub = BSE::SubscriptionTypes->getByPkey($id)
    or return _refresh_list($req, "Cannot find record $id");

  return sub_form($req, 'admin/subs/delete', $sub, 0);
}

sub req_delete {
  my ($class, $req) = @_;

  my $cfg = $req->cfg;
  my $q = $req->cgi;

  my $id = $q->param('id')
    or return _refresh_list($req, "No id supplied to be deleted");

  my $sub = BSE::SubscriptionTypes->getByPkey($id)
    or return _refresh_list($req, "Cannot find record $id");

  $sub->remove;

  return _refresh_list($req, "Subscription deleted");
}
