package BSE::ComposeMail;
use strict;
use BSE::Template;
use BSE::Mail;
use Carp 'confess';
use Digest::MD5 qw(md5_hex);

=head1 NAME

BSE::ComposeMail - compose mail for BSE

=head1 SYNOPSIS

  # make an object
  my $mailer = BSE::ComposeMail->new($cfg);

  # simple stuff
  $mailer->send(to=>$  

=cut

sub new {
  my ($class, %opts) = @_;

  $opts{cfg} or die;

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

  $self->{content} = '';
  $self->{type} = '';
  if (ref $self->{to}) {
    # being sent to a site user, use their setting
    $self->{allow_html} = $self->{to}->allow_html_email;
    $self->{to} = $self->{to}{email};
  }
  else {
    $self->{allow_html} = 
      $self->{cfg}->entry('mail', 'html_system_email', 0);
  }
  
  delete $self->{baseid};
  $self->{attachments} = [];
  $self->{encrypt} = 0;

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
}

sub done {
  my ($self) = @_;

  my %acts = %{$self->{acts}}; # at some point we'll add extra tags here

  my $content = BSE::Template->get_page($self->{template}, $self->{cfg}, \%acts);
  my $text_type = 'text/plain';
  if ($self->{encrypt}) {
    $content = $self->_encrypt($content, \$text_type);
  }
  my @headers;
  my $message;
  if (@{$self->{attachments}}) {

    my $boundary = $self->{baseid}."boundary";
    push @headers, "MIME-Version: 1.0";
    push @headers, qq!Content-Type: multipart/mixed; boundary="$boundary"!;

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
    push @headers, 
      "Content-Type: $text_type",
	"MIME-Version: 1.0";
    $message = $content;
  }

  my $mailer = BSE::Mail->new(cfg => $self->{cfg});
  my $headers = join "", map "$_\n", @headers;
  if ($mailer->send(to => $self->{to},
		    from => $self->{from},
		    subject => $self->{subject},
		    body => $message,
		    headers => $headers)) {
    return 1;
  }
  else {
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

  my $result = $encryptor->encrypt($self->{to}, $content, %opts)
    or die "Cannot encrypt ",$encryptor->error;

  if ($cfg->entry('shop', 'crypt_content_type', 0)) {
    $$rtype = 'application/pgp; format=text; x-action=encrypt';
  }

  $result;
}

sub errstr {
  $_[0]{errstr};
}


1;
