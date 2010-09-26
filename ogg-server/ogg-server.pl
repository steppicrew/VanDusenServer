#!/usr/bin/perl
use warnings;
use strict;

use Symbol qw(gensym);
use HTTP::Response;

use File::Spec;
use URI::Escape;

use Conf;

my %conf= %{Conf::GetConfdata()};
my $port= $conf{port} || 8081;

sub buildInFileName {
        my $reqFile= shift;
        return File::Spec->catfile($conf{basedir}, $reqFile);
}

sub buildTheoraCommand {
        my $sFile= shift || '';
        $sFile=~ s/\\/\\\\/g;
        $sFile=~ s/\"/\\\"/g;
        return 'ffmpeg2theora --novideo --output /dev/stdout "' . $sFile . '"';
}

# Include POE, POE::Component::Server::TCP, and the filters necessary
# to stream web content.
use POE qw(Component::Server::TCP Filter::HTTPD Filter::Stream);


sub closeConnection {
    my ($kernel, $heap)= @_;
    if ($heap->{pid}) {
        kill 9, $heap->{pid};
        waitpid $heap->{pid}, 0;
    }
    delete $heap->{file_name};
    delete $heap->{stream_fh};
    delete $heap->{pid};
    $kernel->yield("shutdown");
}


# Spawn a web server on port 8081 of all interfaces.
POE::Component::Server::TCP->new(
    Alias                => "web_server",
    Port                 => $port,
    ClientFilter => 'POE::Filter::HTTPD',

    ClientDisconnected => sub {
        my ($kernel, $heap) = @_[KERNEL, HEAP];
        closeConnection($kernel, $heap);
    },

    # Output has been flushed to the client.    If the output was
    # headers, open and begin streaming content.    Otherwise continue
    # streaming content until it has all been sent.    An error, such as
    # when the user stops a transfer, will also halt the stream.
    ClientFlushed => sub {
        my ($kernel, $heap) = @_[KERNEL, HEAP];

        # The first flush means that headers were sent.    Open the file
        # to be streamed, and switch to POE's Stream filter.    This
        # allows the content to pass through POE without being changed.
        unless ($heap->{stream_fh}) {
            my $file_handle = $heap->{stream_fh} = gensym();
            my $file_name= $heap->{file_name};
            unless ($file_name && -r $file_name) {
                return closeConnection($kernel, $heap);
            }
            $heap->{pid}= open($file_handle, "-|", buildTheoraCommand($file_name));

            # So that DOS-like systems do not perform ASCII transfers.
            binmode($file_handle);
            $heap->{client}->set_output_filter(POE::Filter::Stream->new());
        }

        # If a chunk of the streaming file can be read, send it to the
        # client.    Otherwise close the file and shut down.
        my $bytes_read = sysread($heap->{stream_fh}, my $buffer = '', 4096);
        if ($bytes_read) {
            $heap->{client}->put($buffer);
        }
        else {
            closeConnection($kernel, $heap);
        }
    },

    # A request has been received from the client.    We ignore its
    # content, but the server could be expanded to stream different
    # files based on what was asked here.
    ClientInput => sub {
        my ($kernel, $heap, $request) = @_[KERNEL, HEAP, ARG0];

        # Filter::HTTPD sometimes generates HTTP::Response objects.
        # They indicate (and contain the response for) errors.    It's
        # easiest to send the responses as they are and finish up.
        if ($request->isa("HTTP::Response")) {
            $heap->{client}->put($request);
            $kernel->yield("shutdown");
            return;
        }

        my $sInFile= uri_unescape $request->uri->path;
        my $sFile= buildInFileName($sInFile);
# print "requested: " . $request->method() . " '$sInFile' ->> '$sFile'\n";
        $heap->{file_name}= $sFile;
        unless (-f $sFile) {
            my $response = HTTP::Response->new(404);
            $response->content("Could not find file '$sInFile'");
            $heap->{client}->put($response);
            return;
        }

        # The request is real and fully formed.    Create and send back
        # headers in preparation for streaming the music.
        my $response = HTTP::Response->new(200);
        $response->push_header('Content-type', 'audio/ogg');
        $heap->{client}->put($response);

        # Note that we do not shut down here.    Once the response's
        # headers are flushed, the ClientFlushed callback will begin
        # streaming the actual content.
    }
);

print "running encoding server on port $port\n";
# Start POE. This will run the server until it exits.
$poe_kernel->run();
exit 0;

