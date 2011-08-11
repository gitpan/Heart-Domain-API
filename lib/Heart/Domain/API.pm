package Heart::Domain::API;

use 5.006;
use warnings;
use strict;
use File::Basename 'dirname';
use IO::Socket::SSL;

our $VERSION = '0.1';

=head1 NAME

Heart::Domain::API - Interface to the Heart Internet Domain Reseller API

=head1 SYNOPSIS

    # The below example connects to the Heart Internet Domain API
    # Automatically logs in using the clid and pw vars and performs a 
    # domain lookup. The extension(s) must be passed in an array.
    # whois() will return false (0) on an unsuccessful lookup, or a 
    # HASH if it succeeds.

    use Heart::Domain::API;
    
    my $h = Heart::Domain::API->new; # accepts default configuration with no extra arguments

    $h->vars(
        clid   => 'ccf0049fd0f38c61',   # for logging in
        pw     => 'FSAFDSfdsfa',        # for logging in
        cltrid => $h->gen_trID          # generate a random transaction id for the session
    );

    # pasing 1 in connect() will force SSL hostname verification
    if ($h->connect(1)) {
        if (my %result = $h->whois('mydomain.com', qw/.com .co.uk .net/)) {
            for (keys %result) {
                my $avail = ($result{$_}) ? 'Available' : 'Not Available';
                print "The domain, $_, is $avail for registration\n";
            }
        }
    }

=head1 DESCRIPTION

This module is used as a 'SDK' to Heart Internet's API. Using Heart::Domain::API there's no 
need to parse complex XML structures or worry about SSL Sockets. Quickly add a new contact, 
perform a domain lookup or create your own templates to use other calls that have not been 
implemented by Heart::Domain::API.
Please note this module is under heavy construction and the author is in no way affiliated 
with Heart Internet.
Please let me know if you'd like anything added/changed :-)
=cut

=head2 test

Usage:

    my $h = Heart::Domain::API->new;
    unless( $h->test ) {
        print "Oh noes! Didn't load properly :/\n";
    }

Purpose: Test simply makes sure the module loaded OK. Doesn't do much, really.
Returns: 0 if it errors, or 1 on successful check.
=cut

sub test {
    if (__PACKAGE__ eq 'Heart::Domain::API') {
        return 1;
    }
    else {
        return 0;
    }
}

=head2 new

Usage:

    my $h = Heart::Domain::API->new(
        -server     => 'customer.heartinternet.co.uk',
        -port       => 700,
        -debug      => 1,
        -path       => '/usr/local/myapp/var'
    );

Purpose: The constructor. You can override default configuration here also.
=cut

sub new {
    my ($class, %a) = @_;
    
    my $self = {
        -test       => $a{-test}||0,
        -server     => $a{-server}||'customer.heartinternet.co.uk',
        -port       => do {
            if (exists $a{-test} && $a{-test}) {
                '1701';
            }
            else {
                $a{-port}||700;
            }
        },
        -path      => $a{-path}||dirname($0),
        -debug    => $a{-debug}||0,
        namespace => $a{namespace}||'urn:ietf:params:xml:ns:epp-1.0',
    };

    unless (-d $self->{-path} . '/Template') {
        die "Could not locate Template folder in '$self->{-path}'\n";
    }
    bless $self, $class;
    return $self;
}  

=head2 vars

Usage:

    my $h = Heart::Domain::API->new;

    $h->vars(
        domain  => 'example.com',
        cltrid  => $h->gen_trID
    );
 
Purpose: Sets variables that can be used within the templates
=cut

sub vars(\%) {
    my ($self, %v) = @_;

    while((my $key, my $val) = each(%v)) {
        $self->{$key} = $val;
    }
}

=head2 connect

Usage:

    my $h = Heart::Domain::API->new;

    $h->vars(
        clid    => 'myclid',
        pw      => 'mypass'
    );

    $h->connect(1);

Purpose: Connects to the Heart Internet API using the information in vars()
Arguments: Pass 1 as an argument to enable hostname verification
=cut

sub connect {
    my ($self, $verify) = @_;

    if ($self->{-debug}) {
        my $testing = ($self->{-test}) ? 'ON' : 'OFF';
        my $verhost = ($verify) ? 'ON' : 'OFF';
        print "[debug] Testing Mode (Sandbox): $testing\n";
        print "[debug] SSL Hostname Verification: $verhost\n";
        print "[debug] Connecting to ", $self->{-server}, ":", $self->{-port}, " ...\n";
    }

    my $cin = $self->{-server} . ':' . $self->{-port};
    $self->{-sock} = IO::Socket::SSL->new( 
        PeerHost => $self->{-server},
        PeerPort => $self->{-port},
        Timeout => 10
    ) or do {
        my $sockerr = IO::Socket::SSL::errstr();
        print "[error] Failed connection to $cin: $sockerr\n" if ($self->{-debug});
        return 0;
    };
    
    if ($verify) {
        $self->{-sock}->verify_hostname( $self->{-server}, 'http' ) or do {
            my $sockerr = IO::Socket::SSL::errstr();
            print "[error] Hostname verification failed: $sockerr\n" if ($self->{-debug});
            return 0;
        }
    }
    return $self->response( $self->{-sock} );
}

sub render {
    my ($self, $template, $temp_path) = @_;

    if (! defined $self->{-template_path} && ! defined $temp_path) {
        $temp_path = $self->{-path} . '/Template/';
    }
    else {
        $temp_path = 'Template/' . $self->{-template_path} if (exists $self->{-template_path});
    }
    $template = $temp_path .  ucfirst(lc($template)) . '.xml';
    print "[debug] Rendering template, $template\n" if ($self->{-debug});
    if (! -f $template) {
        print "[error] Could not locate: $template\n" if ($self->{-debug});
        return 0;
    }
    my $output = "";
    open(XML, "<$template") or do {
        print "[error] Could not open '$template': $!\n" if ($self->{-debug});
        return 0;
    };
    
    while(<XML>) {
        $output .= $_;
    }
    close XML;

    $output =~ s/\[\[(.+)\]\]/$self->{$1}/g;
    if ($self->{-debug}) {
        print "[debug] OUTPUT:\n\n";
        for my $line (split "\n", $output) {
            print "[debug] $line\n";
        }
    }
    
    $self->{output} = $output;
    $self->{template} = $template;
    return 1;
}

sub parse {
    my ($self) = @_;
    my $server = $self->{-sock};

    print $server pack("N", length($self->{output})+4).$self->{output};
    {
        my $response = $self->response($server);
        if ($response) {
            use XML::Simple;
            my $result = XMLin($response);
            return $result;
        }
        else {
            print "[error] Bad response from $self->{-server} on template $self->{template}\n" if ($self->{-debug});
            return 0;
        }
    }
}

sub gen_trID {
    my ($self, $id) = @_;

    use Digest::MD5 'md5_hex';
    if (defined $id) { $id = md5_hex($id); }
    else {
        my @ary = (
            'Rabbit',
            'Duck',
            'Lizard',
            'Penguin'
        );
        $id = md5_hex( $ary[rand($#ary-1)] );
    }

    $self->{cltrid} = $id;
    return $id;
}

sub login {
    my ($self, $id) = @_;

    
    if (! $self->{-sock}->connected()) {
        print "[error] Socket does not exist!\n" if ($self->{-debug});
        return 0;
    }

    $self->gen_trID;

    if ($self->render('Login')) {
        if (my $result = $self->parse) {
            # if result == 1000 then OK
            if ($result->{response}->{result}->{code} eq '1000') {
                return 1;
            }
            else {
                return 0;
            }
        }
    }

    return 0;
}

sub is_connected {
    my $self = shift;
    if (! $self->{-sock}->connected()) {
        print "[error] Socket does not exist!\n" if ($self->{-debug});
        die "Socket is not connected\n";
    }
}

sub whois($\@) {
    my ($self, $domain, @ext) = @_;

    $self->is_connected();

    my @tmp = ();
    for my $i (@ext) {
        push(@tmp, "<ext-domain:ext>$i</ext-domain:ext>");
    }

    for (my $j = 0; $j < $#tmp+1; ++$j) {
        $self->{whois_ext} .= $tmp[$j];
        if ($j != $#tmp+1) { print "\n"; }
    }

    if ($self->login) {
        $self->{domain} = $domain;
        $self->{cltrid} = $self->gen_trID;
        if ($self->render('Whois')) {
            if (my $result = $self->parse) {
                if ($result->{response}->{result}->{code} eq '1000') {
                    my @res = $result->{response}->{resData}->{'domain:chkData'}->{'domain:cd'};
                    my %lookup = ();
                    if (ref $res[0] eq 'ARRAY') {
                        for (@{ $res[0] }) {
                            $lookup{$_->{'domain:name'}->{content}} = $_->{'domain:name'}->{avail};
                        }
                        return %lookup;
                    }
                    else {
                        my $d = $result->{response}->{resData}->{'domain:chkData'}->{'domain:cd'}->{'domain:name'}->{content};
                        my $a = $result->{response}->{resData}->{'domain:chkData'}->{'domain:cd'}->{'domain:name'}->{avail};
                        my %sres = ();
                        $sres{$d} = $a;
                        return %sres;
                    }
                }
                else {
                    return 0;
                }
            }
        }
    }
}

sub logout {
    my ($self) = @_;

    if (! $self->{-sock}->connected()) {
        print "[error] Socket does not exist!\n" if ($self->{-debug});
        return 0;
    }

    if ($self->render('Logout')) {
        if (my $result = $self->parse) {
            if ($result->{response}->{result}->{code} eq '1500') {
                return 1;
            }
            else {
                if ($self->{-debug}) {
                    for my $line (split "\n", $self->dump( $result )) {
                        print "[debug] $line\n";
                    }
                }
                return 0;
            }
        }
    }
    
    return 0;
}

sub response {
    my $self = shift;
    my $size_packed;
    read($self->{-sock}, $size_packed, 4);
    my $size = unpack("N", $size_packed);
    my $response;
    read($self->{-sock}, $response, $size-4);
    return $response;
}

sub dump {
    my ($self, $obj, $nl) = @_;
    use Data::Dumper;
    
    my $ret = Dumper( $obj );
    $ret .= "\n" if ($nl);
    return $ret;
}
1;
