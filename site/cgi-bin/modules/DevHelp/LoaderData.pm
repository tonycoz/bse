package DevHelp::LoaderData;
use strict;
use Carp 'confess';

sub new {
  my ($class, $file, %opts) = @_;
  
  my $intro = <$file>;
  chomp $intro;
  my $result;
  if ($intro eq '--') {
    $result = DevHelp::LoaderData::Fields->new($file);
  } 
  elsif ($intro eq '---') {
    $result = DevHelp::LoaderData::FieldsDefaulted->new($file);
  } 
  elsif ($intro =~ /\t/) {
    $result = DevHelp::LoaderData::Tab->new($file, $intro);
  }
  else {
    $result = DevHelp::LoaderData::CSV->new($file, $intro);
  }
  $result->_set_opts(%opts);

  $result;
}

sub _readline {
  my ($self) = @_;

  $self->{eof} and return;

  my $file = $self->{file};

  my $line = <$file>;
  unless (defined $line) {
    ++$self->{eof};
    return;
  }
  chomp $line;
  while ($line =~ /\\$/) {
    chop $line;
    my $next = <$file>;
    unless (defined $next) {
      ++$self->{eof};
      last;
    }
    $line .= $next;
    chomp $line;
  }

  #print "_readline: $line\n";
  $line;
}

sub _untabify {
  my ($value) = @_;

  while ((my $pos = index($value, "\t")) >= 0) {
    substr($value, $pos, 1) = " " x (8 - $pos % 8);
  }

  $value;
}

my %escapes =
  (
   n => "\n",
   t => "\t",
   r => "\r",
   '"' => '"',
   "'" => "'",
   ' ' => ' ',
   "\n" => '',
   "\\" => "\\",
  );

sub _unescape_code {
  my ($code) = @_;

  if (exists $escapes{$code}) {
    return $escapes{$code};
  }
  elsif ($code =~ /^\d+$/) {
    return chr(oct($code));
  }
  elsif ($code =~ /^x/) {
    return chr(oct("0$code"));
  }
  else {
    confess "Internal error: cannot convert $code";
  }
}

sub _unescape {
  my ($self, $value) = @_;

  $value =~ s/\\([0-7]{1,3}|x[\da-fA-F][\da-fA-F]|[ntr \"\'\n\\])/
    _unescape_code($1)/eg;

  $value;
}

sub _read_heredoc {
  my ($self, $word) = @_;

  my $file = $self->{file};
  my @lines;
  my $start = $.;
  while (defined(my $line = <$file>)) {
    $line = _untabify($line);
    if ($line =~ /^( *)$word\n?$/) {
      my $indent = $1;
      my $pos = 0;
      for my $work (@lines) {
        unless ($work =~ s/^$indent//) {
          warn "Line $. doesn't match terminator indent\n";
        }
        ++$pos;
      }
      return join '', @lines;
    }
    push @lines, $self->_unescape($line);
  }
  die "Could not find end of '$word' heredoc started on line $start\n";
}

sub _set_opts {
  my ($self, %opts) = @_;

  if (exists $opts{noheredoc}) {
    $self->{noheredoc} = $opts{noheredoc};
  }
}

package DevHelp::LoaderData::Fields;
use vars qw(@ISA);
@ISA = qw(DevHelp::LoaderData);

sub new {
  my ($class, $file) = @_;

  return bless { file => $file }, $class;
}

sub read {
  my ($self) = @_;

  my %data;
  while (my $line = $self->_readline) {
    $line =~ /\S/ or last;
    $line =~ /^\s*#/ and next;
    my ($name, $value) = split /:\s?/, $line, 2;
    if ($value =~ /^<<(\w+)$/) {
      $value = $self->_read_heredoc($1);
    }
    else {
      $value = $self->_unescape($value);
    }
    $data{$name} = $value;
  }

  keys %data or return;

  return \%data;
}

package DevHelp::LoaderData::FieldsDefaulted;
use vars qw(@ISA);
@ISA = qw(DevHelp::LoaderData::Fields);

sub new {
  my ($class, $file) = @_;

  my $self = $class->SUPER::new($file);
  $self->{defaults} = $self->SUPER::read() || {};

  return $self;
}

sub read {
  my ($self) = @_;

  my $values = $self->SUPER::read()
    or return;

  for my $key (keys %{$self->{defaults}}) {
    exists $values->{$key} or $values->{$key} = $self->{defaults}{$key};
  }

  return $values;
}

package DevHelp::LoaderData::CSV;
use vars qw(@ISA);
@ISA = qw(DevHelp::LoaderData::Delimited);

sub new {
  my ($class, $file, $intro) = @_;

  my @fields = split /,/, $intro;

  @fields or confess("Invalid intro $intro\n");

  return bless { file => $file, fields=>\@fields, sep => "," }, $class;
}

package DevHelp::LoaderData::Tab;
use vars qw(@ISA);
@ISA = qw(DevHelp::LoaderData::Delimited);

sub new {
  my ($class, $file, $intro) = @_;

  my @fields = split /\t/, $intro;

  @fields or confess("Invalid intro $intro\n");

  return bless { file => $file, fields=>\@fields, sep => "\t" }, $class;
}

package DevHelp::LoaderData::Delimited;
use vars qw(@ISA);
@ISA = qw(DevHelp::LoaderData);

sub read {
  my ($self) = @_;

  my %data;
  my $index = 0;
  my $line = $self->_readline;
  while (defined $line && $line =~ /^\s*\#/) {
    $line = $self->_readline;
  }
  my $sep = $self->{sep};
  defined $line or return;
  while ($line ne '') {
    if ($index >= @{$self->{fields}}) {
      warn "Line $.: too many input fields\n";
      last;
    }
    if (!$self->{noheredoc} && $line =~ s/^<<(\w+)(?=$sep|$)//) {
      $data{$self->{fields}[$index++]} = $self->_read_heredoc($1);
    }
    elsif ($line =~ s/^\"((?:[^\"\\]|\\(?:[\"\'\\ntr ]|x[\da-fA-F][\da-fA-F]|[0-7]{1,3}))*)\"(?=$sep|$)//) {
      $data{$self->{fields}[$index++]} = $self->_unescape($1);
    }
    elsif ($line =~ s/^NULL\s*(?=$sep|$)//) {
      $index++;
    }
    elsif ($line =~ s/([^$sep]*)(?=$sep|$)//) {
      $data{$self->{fields}[$index++]} = $1;
    }
    else {
      confess("Internal error: could not parse '$line'");
    }
    $line =~ s/^$sep//
      or last;
  }

  return \%data;
}

1;
