package Apache::Session::Store::DBIreal;

our $VERSION = "1.000";

use strict;

use DBI;
use Apache::Session::Store::DBI;

use vars qw(@ISA $VERSION);

@ISA = qw(Apache::Session::Store::DBI);
$VERSION = '1.03';

$Apache::Session::Store::MySQL::DataSource = undef;
$Apache::Session::Store::MySQL::UserName   = undef;
$Apache::Session::Store::MySQL::Password   = undef;

sub connection {
    my $self    = shift;
    my $session = shift;
    
    return if (defined $self->{dbh});

    if (exists $session->{args}->{Handle}) {
        $self->{dbh} = $session->{args}->{Handle};
        return;
    }

    my $datasource = $session->{args}->{DataSource} || 
        $Apache::Session::Store::MySQL::DataSource;
    my $username = $session->{args}->{UserName} ||
        $Apache::Session::Store::MySQL::UserName;
    my $password = $session->{args}->{Password} ||
        $Apache::Session::Store::MySQL::Password;
        
    $self->{dbh} = DBI->connect(
        $datasource,
        $username,
        $password,
        { RaiseError => 1, AutoCommit => 1 }
    ) || die $DBI::errstr;

    
    #If we open the connection, we close the connection
    $self->{disconnect} = 1;    
}

sub DESTROY {
    my $self = shift;
    
    if ($self->{disconnect}) {
        $self->{dbh}->disconnect;
    }
}

1;
