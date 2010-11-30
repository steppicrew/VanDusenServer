#!/usr/bin/perl

use strict;
use warnings;

use Getopt::Long 2.24 qw( :config auto_version bundling );
use Pod::Usage;
use HTTP::Daemon;
use HTTP::Status;
use Data::Dumper;

use lib ".";

use WuiResponse;
use CascadedCSS;

our $VERSION= '0.1';

my $have_module_reload;

our $opt_debug;
our $opt_help;
our $opt_man;

GetOptions( "debug", "help|h", "man|m" ) or pod2usage(2);
pod2usage(-verbose => 1) if $opt_help;
pod2usage(-verbose => 2) if $opt_man;

my $d = HTTP::Daemon->new(
    LocalPort => 8080,
    Reuse => $opt_debug,
) || die;

print "Please contact me at: <URL:", $d->url, ">\n";
print "DEBUG on\n" if $opt_debug;

my $conn;

$SIG{TERM}= $SIG{QUIT}= $SIG{INT}= sub {
    print STDERR "Caught SIGTERM - Closing connection\n";
    $conn->close if $conn;
    exit(0);
};

my %mimetypes= (
    'gif' => 'image/gif',
    'jpg' => 'image/jpeg',
    'png' => 'image/png',
    'css' => 'text/css',
    'ico' => 'image/x-icon',
    'js'  => 'application/x-javascript',
);

sub read_file {
    my $sPath= shift;
    my $fh;
    open $fh, $sPath or return;
    local $/= undef;
    return scalar <$fh>;
}

while ($conn = $d->accept) {
    while (my $request = $conn->get_request) {

        if ($opt_debug && $have_module_reload) {
            Module::Reload->check;
        }

        my $status= RC_FORBIDDEN;
        my $path= $request->uri->path;
        my $params;

        my $mobile= $request->header('host')=~ /^m(obile)?\./;

        print "Requested: [$path]\n" if $opt_debug;
        # print Dumper($request);

        if ($request->method eq 'GET') {
            if ($path =~ /^\/(?:static\/(.*)|(favicon))(\.(.*?))$/) {
                my $ext= $4;
                $path= ($1 || $2) . $3;
                $path =~ s#\.\.+##g;
                $path =~ s/[^-\/\.a-zA-Z0-9_]+//g;
                if (-e "static/$path") {
                    my $response= HTTP::Response->new(200);
                    $response->header(
                        "Content-type" => ($mimetypes{$ext} || "text/html"),
                    );
                    if ($path =~ /\.css$/) {
                        my $css= CascadedCSS->new("static/$path");
                        $response->content($css->render());
                    }
                    else {
                        $response->content(read_file("static/$path"));
                    }
                    $conn->send_response($response);
                    $conn->force_last_request();
                    next;
                }
                $status= RC_NOT_FOUND;
            }
            else {
                $params = { $request->uri->query_form };
            }
        }
        if ($request->method eq 'POST') {

            # I don't know how to elegantly fetch POST params, so that'll have to do:
            my $uri = URI->new("http://localhost/");
            $uri->query($request->content);
            $params= { $uri->query_form };
        }

        my ($hHeader, $content);

        if ($request->method eq 'OPTIONS') {
            $hHeader= {
                'Access-Control-Allow-Methods' => 'POST, GET, OPTIONS',
                'Access-Control-Max-Age' => 86400,
                'Content-Type' => 'text/plain',
            };
            $hHeader->{'Access-Control-Allow-Headers'}= $request->header('Access-Control-Request-Headers') if $request->header('Access-Control-Request-Headers');
            $content= '';
            # print Dumper($request, $hHeader);
        }
        else {
            print Dumper($params) if $params && $opt_debug;
            ($hHeader, $content)= WuiResponse->new(
                path => $path,
                params => $params,
                cookies => scalar $request->header('cookie'),
                debug => $opt_debug,
                mobile => $mobile,
            )->build();
            # print Dumper($request, $hHeader);
            # print $content, "\n";
        }

        $hHeader->{'Access-Control-Allow-Origin'}= '*';

        if (defined $content) {
            my $response= HTTP::Response->new(200);
            $response->header(%$hHeader);
            $response->content($content);
            $conn->send_response($response);
            $conn->force_last_request();
            next;
        }
        $status= RC_NOT_FOUND;
        $conn->send_error($status, status_message($status));
        $conn->force_last_request();
    }
    $conn->close;
    undef($conn);
}
