package BSE::ComposeMail;
use strict;
use BSE::Template;
use BSE::Mail;
use Carp 'confess';
use Digest::MD5 qw(md5_hex);
use BSE::Variables;

our $VERSION = "1.010";

=head1 NAME

BSE::ComposeMail - compose mail for BSE

=head1 SYNOPSIS

  # make an object
  my $mailer = BSE::ComposeMail->new(cfg => $cfg);

  # simple stuff
  # to can either be an email (assumed to be a sysadmin email)
  # or a member object (used to determine text or text and html)
  # but this text vs mixed is unimplemented for now
  $mailer->send(to       => $member_object,
                subject  => $subject,
                template => $template,
                acts     => \%acts,
                # from   => $from,
                # html_template => $html_template # def $template."_html"
                # vars   => \%vars,
                ) or die $mailer->errstr;

  # more complex
  $mailer->start( ... parameters as above ...);

  # attach a file
  my $cidurl = $mailer->attach(file => $filename,
                               # disposition => 'attachment',
                               # display     => $filename,
                               # type        => 'application/octet-stream'
                               ) or die $mailer->errstr;
  # display required unless disposition set to other than "attachment"
  my $cidurl2 = $mailer->attach(fh => $fh,
                                display => $display_filename,
                                ...);
  my $cidurl3 = $mailer->attach(data => $data,
                                display => $display_filename,
                                ...);

  # encrypt and sign
  $mailer->encrypt_body(signing_id => $id,
                        passphrase => $passphrase);

  # encrypt unsigned
  $mailer->encrypt_body(signing_id => '');

  # encrypt signed based on the [shop].crypt_signing_id
  $mailer->encrypt_body();

  # and send it
  $mailer->done() or die $mailer->errstr;

=cut

sub new {
  my ($class, %opts) = @_;

  $opts{cfg} ||= BSE::Cfg->single;

  bless \%opts, $class;
}

sub send {
  my ($self, %opts) = @_;

  $self->start(%opts)
    and $self->done();
}

sub start {
  my ($self, %opts) = @_;

  for my $arg (qw(acts template to subject)) {
    unless ($opts{$arg}) {
      confess "Argument $arg missing\n";
    }
    $self->{$arg} = $opts{$arg};
  }

  $self->{from} = $opts{from} 
    || $self->{cfg}->entry('shop', 'from', $Constants::SHOP_FROM);

  $self->{html_template} = $opts{html_template}
    || "$self->{template}_html";
  
  $self->{extra_mail_args} = {};
  for my $arg (qw(to_name from_name cc bcc)) {
    defined $opts{$arg}
      and $self->{extra_mail_args}{$arg} = $opts{$arg};
  }

  $self->{content} = '';
  $self->{type} = '';
  unless (defined $self->{allow_html}) {
    if (ref $self->{to}) {
      # being sent to a site user, use their setting
      $opts{log_object} ||= $self->{to};
      $self->{allow_html} = $self->{to}->allow_html_email;
      $self->{to} = $self->{to}{email};
    }
    else {
      $self->{allow_html} = 
	$self->{cfg}->entry('mail', 'html_system_email', 0);
    }
  }
  
  delete $self->{baseid};
  $self->{attachments} = [];
  $self->{encrypt} = 0;

  $self->{log} =
    {
     actor => "S",
     component => "composemail::send",
    };
  for my $key (keys %opts) {
    if ($key =~ /^log_(\w+)$/) {
      $self->{log}{$1} = $opts{$key};
    }
  }

  my $weak = $self;
  Scalar::Util::weaken($weak);
  $self->{vars} =
    {
     bse => BSE::Variables->variables(),
     cfg => $self->{cfg},
     set_subject => sub {
       $self->{subject} = $_[0];
     },
     ( $opts{vars} ? %{$opts{vars}} : () ),
    };

  1;
}

sub _gen_id {
  my ($self) = @_;

  unless ($self->{baseid}) {
    # something sort of random
    $self->{baseid} = md5_hex(join(",", time, map rand, 0..15));
    $self->{idseq} = 0;
  }

  return $self->{baseid} . "." . ++$self->{idseq};
}

sub attach {
  my ($self, %opts) = @_;

  my $disp = $opts{disposition} || 'attachment';
  my $display = $opts{display};
  if ($disp eq 'attachment' && !$display) {
    if ($opts{file}) {
      ($display = $opts{file}) =~ s!.*[/:\\]!!;
      $display =~ tr/a-zA-Z_./_/cs;
    }
    else {
      $self->{errstr} = "You must supply display to attach() if you don't supply file";
      return;
    }
  }

  if ($opts{file}) {
    # don't attach the same file twice if we can avoid it
    for my $attachment (@{$self->{attachments}}) {
      if ($attachment->{file} && $attachment->{file} eq $opts{file}) {
	return $attachment->{url};
      }
    }
  }

  my $id = $self->_gen_id;
  my $url = "cid:$id";
  my $type = $opts{type} || 'application/octet-stream';

  if ($opts{file}) {
    unless (-e $opts{file}) {
      $self->{errstr} = "Attachment file $opts{file} doesn't exist";
      return;
    }

    push @{$self->{attachments}},
      {
       file => $opts{file},
       disposition => $disp,
       display => $display,
       id => $id,
       url => $url,
       type => $type
      };
  }
  elsif ($opts{fh}) {
    push @{$self->{attachments}},
      {
       fh => $opts{fh},
       disposition => $disp,
       display => $display,
       id => $id,
       url => $url,
       type => $type
      };
  }
  elsif ($opts{data}) {
    push @{$self->{attachments}},
      {
       data => $opts{data},
       disposition => $disp,
       display => $display,
       id => $id,
       url => $url,
       type => $type
      };
  }
  else {
    $self->{errstr} = "No file/fh/data supplied to attach()";
    return;
  }

  return $url;
}

sub encrypt_body {
  my ($self, %opts) = @_;

  $self->{encrypt} = 1;
  $self->{signing_id} = $opts{signing_id};
  $self->{passphrase} = $opts{passphrase};
  $self->{crypt_recipient} = $opts{recipient};
}

sub _build_internal {
  my ($self, $content, $text_type, $headers) = @_;

  my $message;
  if (@{$self->{attachments}}) {

    my $boundary = $self->{baseid}."boundary";
    push @$headers, "MIME-Version: 1.0";
    push @$headers, qq!Content-Type: multipart/mixed; boundary="$boundary"!;

    $message = <<EOS;
--$boundary
Content-Type: $text_type
Content-Disposition: inline

$content
EOS
    for my $attachment (@{$self->{attachments}}) {
      my $data;
      if ($attachment->{file}) {
	if (open DATA, "< $attachment->{file}") {
	  binmode DATA;
	  $data = do { local $/; <DATA> };
	  close DATA;
	}
	else {
	  $self->{errstr} = "Could not open attachment $attachment->{file}: $!";
	  return;
	}
      }
      elsif ($attachment->{fh}) {
	my $fh = $attachment->{fh};
	binmode $fh;
	$data = do { local $/; <$fh> };
      }
      elsif ($attachment->{data}) {
	$data = $attachment->{data};
      }
      else {
	confess "Internal error: attachment with no file/fh/data";
      }

      my $is_text = $attachment->{type} =~ m!^text/!
	&& $data =~ tr/ -~\r\n\t//c;

      my $encoding;
      my $encoded;
      # we might add 7bit here at some point
      if ($is_text) {
	require MIME::QuotedPrint;
	$encoded = MIME::QuotedPrint::encode_qp($data);
	$encoding = 'quoted-printable';
      }
      else {
	require MIME::Base64;
	$encoded = MIME::Base64::encode_base64($data);
	$encoding = 'base64';
      }
      my $disp = $attachment->{disposition};
      if ($disp eq 'attachment') {
	$disp .= qq!; filename="$attachment->{display}"!;
      }
      $message .= <<EOS;
--$boundary
Content-Type: $attachment->{type}
Content-Transfer-Encoding: $encoding
Content-Disposition: $disp
Content-Id: <$attachment->{id}>

$encoded
EOS
    }
    $message =~ /\n\z/ or $message .= "\n";
    $message .= "--$boundary--\n";
  }
  else {
    push @$headers, 
      "Content-Type: $text_type",
	"MIME-Version: 1.0";
    $message = $content;
  }

  return $message;
}

sub _build_mime_lite {
  my ($self, $text_content, $html_content, $headers) = @_;
  
  require MIME::Lite;

  $text_content .= "\n" unless $text_content =~ /\n$/;
  $html_content .= "\n" unless $html_content =~ /\n$/;

  my $charset = $self->{cfg}->charset;

  my $msg = MIME::Lite->new
    (
     From => $self->{from},
     "Errors-To:" => $self->{from},
     Subject => $self->{subject},
     Type => 'multipart/alternative',
    );
  my $text_part = $msg->attach
    (
     Type => "text/plain; charset=$charset",
     Data => [ $text_content ],
     $text_content =~ /.{79}/ || $text_content =~ /[^ -~\x0d\x0a]/
     ? ( Encoding => 'quoted-printable' ) : (),
    );
  my $html_part = $msg->attach(Type => 'multipart/related');
  $html_part->attach
    (
     Type => BSE::Template->html_type($self->{cfg}),
     Data => $html_content,
     Encoding => 'quoted-printable',
    );

  for my $attachment (@{$self->{attachments}}) {
    my $data;
    if ($attachment->{file}) {
      if (open DATA, "< $attachment->{file}") {
	binmode DATA;
	$data = do { local $/; <DATA> };
	close DATA;
      }
      else {
	$self->{errstr} = "Could not open attachment $attachment->{file}: $!";
	return;
      }
    }
    elsif ($attachment->{fh}) {
      my $fh = $attachment->{fh};
      binmode $fh;
      $data = do { local $/; <$fh> };
    }
    elsif ($attachment->{data}) {
      $data = $attachment->{data};
    }
    else {
      confess "Internal error: attachment with no file/fh/data";
    }
    my %opts =
      (
       Type => $attachment->{type},
       Data => $data,
       Id   => "<$attachment->{id}>" # <> required by RFC
      );
    if ($attachment->{disposition} eq 'attachment' || $attachment->{display}) {
      $opts{Filename} = $attachment->{display};
    }
    $html_part->attach(%opts);
  }

  my $header_str = $msg->header_as_string;
  for my $header (split /\n/, $header_str) {
    my ($key, $value) = $header =~ /^([^:]+): *(.*)/
      or next;
    # the mailer adds these in later
    unless ($key =~ /^(from|to|subject)$/i) {
      push @$headers, $header;
    }
  }

  return $msg->body_as_string;
}

sub extra_headers {
  my ($self) = @_;

  my $section = $self->{header_section} || "mail headers for $self->{template}";
  my @headers;
  my %extras = $self->{cfg}->entriesCS($section);
  for my $key (keys %extras) {
    (my $head_key = $key) =~ s/_/-/g;
    push @headers, "$head_key: $extras{$key}";
  }
  
  return @headers;
}

sub _log_dump {
  my ($self, $headers, $message) = @_;

  my $max = $self->{cfg}->entry("audit log", "mail_max_dump", 50000);
  my $msg = "$headers\n\n$message";
  if (length($msg) > $max) {
    substr($msg, $max-3) = "...";
  }

  return $msg;
}

sub done {
  my ($self) = @_;

  my %acts = 
    (
     %{$self->{acts}},
     resource => [ tag_resource => $self ],
     set_subject => [ tag_set_subject => $self ],
    ); # 

  my $message;
  my @headers;
  my $content = BSE::Template->
    get_page($self->{template}, $self->{cfg}, \%acts, undef, undef, $self->{vars});

  $content = BSE::Template->encode_content($content, $self->{cfg});

  if (!$self->{allow_html} || $self->{encrypt} || 
      !BSE::Template->find_source($self->{html_template}, $self->{cfg})) {
    my $text_type = 'text/plain';
    if ($self->{encrypt}) {
      $content = $self->_encrypt($content, \$text_type);
      $content
	or return;
    }
    $message = $self->_build_internal($content, $text_type, \@headers);
  }
  else {
    my $html_content = BSE::Template->
      get_page($self->{html_template}, $self->{cfg}, \%acts, undef, undef, $self->{vars});

    my $inline_css = $self->{cfg}->entry("mail", "inline_css", "style");
    if (($inline_css eq "style" && $html_content =~ /<style/i)
	|| $inline_css eq "force") {
      my $report_failure = $self->{cfg}->entry("mail", "inline_css_report", 1);
      my %inline_opts = map { $_ => 1 } split /,/,
	$self->{cfg}->entry("mail", "inline_css_flags", "");
      my $good = eval {
	require CSS::Inliner;
	my $inliner = CSS::Inliner->new(\%inline_opts);
	local $SIG{__DIE__};
	$inliner->read({html => $html_content});
	$html_content = $inliner->inlinify;
	1;
      };
      if (!$good && $report_failure) {
	my $error = $@;
	require BSE::TB::AuditLog;
	my %log = %{$self->{log}};
	my $dump = <<DUMP;
HTML:
======
$html_content
======
Error:
======
$error
======
DUMP
	BSE::TB::AuditLog->log
	    (
	     %log,
	     msg => "Error inlining CSS",
	     component => "composemail:done:inlinecss",
	     level => "error",
	     dump => $dump,
	    );
      }
    }

    $html_content = BSE::Template->encode_content($html_content, $self->{cfg});

    $message = $self->_build_mime_lite($content, $html_content, \@headers);
  }
  push @headers, $self->extra_headers;
  my $mailer = BSE::Mail->new(cfg => $self->{cfg});
  my $headers = join "", map "$_\n", @headers;
  my %extras;
  if ($mailer->send(to => $self->{to},
		    from => $self->{from},
		    subject => $self->{subject},
		    body => $message,
		    headers => $headers,
		    %{$self->{extra_mail_args}})) {
    if ($self->{cfg}->entry("audit log", "mail", 0)) {
      my %log_opts = %{$self->{log}};
      $log_opts{msg} ||= "Mail sent to $self->{to}";
      $log_opts{component} ||= "composemail:done:send";
      $log_opts{level} ||= "info";
      $log_opts{actor} ||= "S";
      $log_opts{dump} =$self->_log_dump($headers, $message);
      require BSE::TB::AuditLog;
      BSE::TB::AuditLog->log(%log_opts);
    }
    return 1;
  }
  else {
    my %log_opts = %{$self->{log}};
    $log_opts{msg} = "Error sending email: " . $mailer->errstr;
    $log_opts{component} ||= "composemail:done:send";
    $log_opts{level} ||= "error";
    $log_opts{actor} ||= "S";
    $log_opts{dump} = $self->_log_dump($headers, $message);
    require BSE::TB::AuditLog;
    BSE::TB::AuditLog->log(%log_opts);
    
    $self->{errstr} = "Send error: ", $mailer->errstr;
    print STDERR "Error sending mail ", $mailer->errstr, "\n";
    return;
  }
}

sub _encrypt {
  my ($self, $content, $rtype) = @_;
  
  my $cfg = $self->{cfg};

  my $crypt_class = $cfg->entry('shop', 'crypt_module', 
				$Constants::SHOP_CRYPTO);
  my $signing_id = defined($self->{signing_id}) ? $self->{signing_id}
    : $cfg->entry('shop', 'crypt_signing_id',
		   $Constants::SHOP_SIGNING_ID);
  my $passphrase = defined($self->{passphrase}) ? $self->{passphrase}
    : $cfg->entry('shop', 'crypt_passphrase', $Constants::SHOP_PASSPHRASE);
  my $gpg = $cfg->entry('shop', 'crypt_gpg', $Constants::SHOP_GPG);
  my $pgp = $cfg->entry('shop', 'crypt_pgp', $Constants::SHOP_PGP);
  my $pgpe = $cfg->entry('shop', 'crypt_pgpe', $Constants::SHOP_PGPE);

  (my $class_file = $crypt_class.".pm") =~ s!::!/!g;
  require $class_file;
  my $encryptor = $crypt_class->new;
  my %opts =
    (
     passphrase => $passphrase,
     stripwarn => 1,
     debug => $cfg->entry('debug', 'mail_encryption', 0),
     sign => !!$signing_id,
     secretkeyid => $signing_id,
     pgp => $pgp,
     pgpe => $pgpe,
     gpg => $gpg,
    );

  my $recip = $self->{crypt_recipient} || $self->{to};

  my $result = $encryptor->encrypt($recip, $content, %opts);
  unless ($result) {
    my $dump = $encryptor->can("dump") ? $encryptor->dump : "See error log";
    require BSE::TB::AuditLog;
    BSE::TB::AuditLog->log
	(
	 %{$self->{log}},
	 msg => "Error encrypting content: " . $encryptor->error,
	 level => "crit",
	 component => "composemail:done:encrypt",
	 dump => $dump,
	);
    $self->{errstr} = "Error encrypting: " . $encryptor->error;
    return;
  }

  if ($cfg->entry('shop', 'crypt_content_type', 0)) {
    $$rtype = 'application/pgp; format=text; x-action=encrypt';
  }

  $result;
}

sub errstr {
  $_[0]{errstr};
}

sub tag_resource {
  my ($self, $args) = @_;

  defined $args and $args =~ /^\w+$/
    or return "** invalid resource id $args **";

  if ($self->{resource}{$args}) {
    return $self->{resource}{$args};
  }

  my $res_entry = $self->{cfg}->entry('mail resources', $args)
    or return "** No resource $args found **";
  my ($filename, $type, $inline) = split /,/, $res_entry;

  unless ($type) {
    if ($filename =~ /\.(gif|png|jpg)$/i) {
      $type = lc $1 eq 'jpg' ? 'image/jpeg' : 'image/' . lc $1;
    }
    else {
      $type = 'application/octet-stream';
    }
  }
  if (!defined $inline) {
    $inline = $type =~ m!^image/!;
  }

  my $abs_filename = BSE::Template->find_source($filename, $self->{cfg})
    or return "** file $filename for resource $args not found **";

  (my $display = $filename) =~ s/.*[\/\\]//;

  my $url = $self->attach(file => $abs_filename,
			  display => $display,
			  type => $type,
			  inline => $inline)
    or return "** could not attach $args: $self->{errstr} **";

  $self->{resource}{$args} = $url;

  return $url;
}

sub tag_set_subject {
  my ($self, $args, $acts, $tag, $templater) = @_;

  my @args = DevHelp::Tags->get_parms($args, $acts, $templater);

  $self->{subject} = "@args";

  return '';
}

sub send_simple {
  my ($class, %opts) = @_;

  my $cfg = BSE::Cfg->single;
  my $mailer = $class->new(cfg => $cfg);

  my $id = $opts{id}
    or confess "No mail id provided";

  my $section = "email $id";

  for my $key (qw/subject template html_template allow_html from from_name/) {
    my $value = $cfg->entry($section, $key);
    defined $value and $opts{$key} = $value;
  }
  unless (defined $opts{acts}) {
    require BSE::Util::Tags;
    BSE::Util::Tags->import(qw/tag_hash_plain/);
    my %acts =
      (
       BSE::Util::Tags->static(undef, $cfg),
      );
    if ($opts{extraacts}) {
      %acts = ( %acts, %{$opts{extraacts}} );
    }
    $opts{acts} = \%acts;
  }

  $mailer->send(%opts)
    or print STDERR "Error sending mail $id: ", $mailer->errstr, "\n";

  return 1;
}


1;
