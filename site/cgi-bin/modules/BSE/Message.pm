package BSE::Message;
use strict;
use Carp qw/confess/;

sub new {
  my ($class, %opts) = @_;

  my $cfg = $opts{cfg}
    or confess "No cfg supplied";
  my $section = $opts{section}
    or confess "No section supplied";

  return 
    sub {
      my ($id, $def, @parms) = @_;
      
      my $msg = $cfg->entry("messages", "$section/$id");
      $msg or return $def;
      
      
      $msg =~ s/\$([\d\$])/$1 eq '$' ? '$' : $parms[$1-1]/eg;
      
      $msg;
    };
}

1;
