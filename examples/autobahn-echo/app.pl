use strict;
use warnings;
use Future::AsyncAwait;
use experimental 'signatures';

# Autobahn-compatible WebSocket echo server
# Returns messages exactly as received (no modification)

async sub app ($scope, $receive, $send) {
    # Handle lifespan
    if ($scope->{type} eq 'lifespan') {
        while (1) {
            my $event = await $receive->();
            if ($event->{type} eq 'lifespan.startup') {
                await $send->({ type => 'lifespan.startup.complete' });
            }
            elsif ($event->{type} eq 'lifespan.shutdown') {
                await $send->({ type => 'lifespan.shutdown.complete' });
                last;
            }
        }
        return;
    }

    # Only handle WebSocket
    return if $scope->{type} ne 'websocket';

    my $event = await $receive->();
    return if $event->{type} ne 'websocket.connect';

    # Accept the connection
    await $send->({ type => 'websocket.accept' });

    # Echo loop - return messages exactly as received
    while (1) {
        my $frame = await $receive->();

        if ($frame->{type} eq 'websocket.receive') {
            # Echo back exactly what we received
            if (defined $frame->{text}) {
                await $send->({
                    type => 'websocket.send',
                    text => $frame->{text}  # Exact echo
                });
            }
            elsif (defined $frame->{bytes}) {
                await $send->({
                    type => 'websocket.send',
                    bytes => $frame->{bytes}  # Exact echo
                });
            }
        }
        elsif ($frame->{type} eq 'websocket.disconnect') {
            last;
        }
    }
}

\&app;
