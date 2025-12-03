package PAGI::Simple::PubSub;

use strict;
use warnings;
use experimental 'signatures';

our $VERSION = '0.01';

use Scalar::Util qw(weaken refaddr);

=head1 NAME

PAGI::Simple::PubSub - In-memory pub/sub system for PAGI::Simple

=head1 SYNOPSIS

    use PAGI::Simple::PubSub;

    my $pubsub = PAGI::Simple::PubSub->instance;

    # Subscribe to a channel
    my $callback = sub ($message) {
        print "Got: $message\n";
    };
    $pubsub->subscribe('chat:general', $callback);

    # Publish to all subscribers
    $pubsub->publish('chat:general', { text => 'Hello!' });

    # Unsubscribe
    $pubsub->unsubscribe('chat:general', $callback);

    # Get subscriber count
    my $count = $pubsub->subscribers('chat:general');

=head1 DESCRIPTION

PAGI::Simple::PubSub provides a simple in-memory pub/sub system for
coordinating messages between WebSocket and SSE connections. It uses
a singleton pattern to ensure all connections share the same state.

This is an internal module primarily used by L<PAGI::Simple::WebSocket>
and L<PAGI::Simple::SSE> for room management and broadcasting.

=head1 ARCHITECTURE

=head2 Singleton Pattern

PubSub uses a singleton pattern (via C<instance()>) to ensure all parts
of your application share the same message bus. This is essential for
real-time features where a WebSocket handler needs to broadcast to SSE
clients, or where multiple route handlers need to communicate.

    # All of these return the same instance
    my $pubsub1 = PAGI::Simple::PubSub->instance;
    my $pubsub2 = PAGI::Simple::PubSub->instance;
    # $pubsub1 and $pubsub2 are the same object

The singleton is process-local, meaning each worker process has its own
independent PubSub instance. See L</SCALING CONSIDERATIONS> for multi-process
deployments.

=head2 Channel Naming Conventions

Channels are simple strings, but using a consistent naming convention
improves code organization:

    # Recommended: Use colons to create namespaces
    chat:general           # General chat room
    chat:room:123          # Specific room by ID
    user:456:notifications # User-specific channel
    system:alerts          # System-wide alerts
    dashboard:metrics      # Dashboard updates

    # Avoid: Inconsistent or unclear names
    generalChat            # Harder to parse
    room123               # No namespace separation

=head2 Message Format

Messages can be any Perl value - scalars, hashrefs, or arrayrefs.
For consistency and extensibility, hashrefs are recommended:

    # Good: Structured messages
    $pubsub->publish('chat:general', {
        type    => 'message',
        user    => 'alice',
        text    => 'Hello everyone!',
        sent_at => time(),
    });

    # Also valid but less flexible
    $pubsub->publish('notifications', "New message received");

Messages are passed by reference, so subscribers receive the same
object. Avoid modifying messages in callbacks if multiple subscribers
exist.

=head1 EXAMPLES

=head2 Chat Room Pattern

A complete chat room implementation using WebSocket and PubSub:

    # In your PAGI::Simple app
    $app->websocket('/chat/:room' => sub ($ws) {
        my $room = $ws->path_params->{room};
        my $channel = "chat:$room";
        my $username = 'anonymous';

        # Handle incoming messages
        $ws->on(message => sub ($msg) {
            my $data = $ws->json_decode($msg);

            if ($data->{type} eq 'join') {
                $username = $data->{username};
                $ws->pubsub->publish($channel, {
                    type => 'system',
                    text => "$username joined the room",
                });
            }
            elsif ($data->{type} eq 'message') {
                $ws->pubsub->publish($channel, {
                    type => 'message',
                    user => $username,
                    text => $data->{text},
                });
            }
        });

        # Subscribe to room messages
        $ws->subscribe($channel, sub ($msg) {
            $ws->send_json($msg);
        });

        # Cleanup on disconnect
        $ws->on(close => sub {
            $ws->pubsub->publish($channel, {
                type => 'system',
                text => "$username left the room",
            });
        });
    });

=head2 Live Notifications Pattern

Server-side event notifications pushed to connected clients:

    # SSE endpoint for notifications
    $app->sse('/notifications/:user_id' => sub ($sse) {
        my $user_id = $sse->path_params->{user_id};
        my $channel = "user:$user_id:notifications";

        $sse->subscribe($channel, sub ($notification) {
            $sse->send_event(
                event => $notification->{type},
                data  => $sse->json_encode($notification),
            );
        });
    });

    # From anywhere in your app (API handler, background job, etc.)
    $app->post('/api/send-notification' => sub ($c) {
        my $body = $c->req->json_body->get;
        my $pubsub = PAGI::Simple::PubSub->instance;

        $pubsub->publish("user:$body->{user_id}:notifications", {
            type    => 'alert',
            title   => $body->{title},
            message => $body->{message},
        });

        $c->json({ sent => 1 });
    });

=head2 Real-Time Dashboard Updates

Broadcasting metrics to all connected dashboard viewers:

    # SSE endpoint for dashboard
    $app->sse('/dashboard/stream' => sub ($sse) {
        $sse->subscribe('dashboard:metrics', sub ($metrics) {
            $sse->send_event(
                event => 'metrics',
                data  => $sse->json_encode($metrics),
            );
        });
    });

    # Background metrics publisher (called periodically)
    sub publish_metrics {
        my $pubsub = PAGI::Simple::PubSub->instance;
        $pubsub->publish('dashboard:metrics', {
            cpu_usage    => get_cpu_usage(),
            memory_usage => get_memory_usage(),
            requests_sec => get_request_rate(),
            timestamp    => time(),
        });
    }

=head1 MEMORY CONSIDERATIONS

=head2 Subscriber Cleanup

Always unsubscribe when connections close to prevent memory leaks.
The WebSocket and SSE helpers do this automatically, but if using
PubSub directly, ensure proper cleanup:

    my $callback = sub ($msg) { ... };
    $pubsub->subscribe('channel', $callback);

    # Later, when done:
    $pubsub->unsubscribe('channel', $callback);

    # Or remove from all channels at once:
    $pubsub->unsubscribe_all($callback);

=head2 High Subscriber Counts

Each subscriber adds memory overhead (callback reference storage).
For thousands of concurrent connections, monitor memory usage.
Consider using channel hierarchies to limit broadcast scope:

    # Instead of one global channel
    $pubsub->publish('all-users', $msg);  # 10,000 callbacks

    # Use regional or segmented channels
    $pubsub->publish('region:us-east', $msg);  # 2,000 callbacks

=head2 Message Size

Large messages are held in memory while being delivered to all
subscribers. For large payloads, consider sending references or IDs
instead of full data:

    # Instead of embedding large data
    $pubsub->publish('updates', { full_document => $huge_blob });

    # Send a reference to fetch
    $pubsub->publish('updates', {
        type => 'document_updated',
        id   => $doc_id,
        url  => "/api/documents/$doc_id",
    });

=head1 LIMITATIONS

=head2 Single-Process Only

PubSub is in-memory and process-local. Messages published in one
worker process are NOT visible to other processes. This means:

=over 4

=item * Works perfectly with single-worker deployments

=item * Works for connections handled by the same worker

=item * Does NOT work across multiple workers or servers

=back

=head2 No Persistence

Messages are fire-and-forget. If no subscribers exist when a message
is published, it's lost. There's no message queue or replay capability.

=head2 No Message Ordering Guarantees

While messages are typically delivered in order within a single
publish call, there's no guaranteed ordering across multiple publishes
or when callbacks take varying amounts of time.

=head1 SCALING CONSIDERATIONS

For multi-process or multi-server deployments, replace the in-memory
PubSub with an external message broker:

=head2 Redis Adapter Pattern

    # Custom Redis-backed PubSub (conceptual example)
    package MyApp::RedisPubSub;

    use Redis::Fast;

    sub instance {
        state $instance = __PACKAGE__->new;
        return $instance;
    }

    sub new ($class) {
        my $self = bless {
            redis     => Redis::Fast->new,
            callbacks => {},
        }, $class;
        return $self;
    }

    sub subscribe ($self, $channel, $callback) {
        # Store callback locally
        push @{$self->{callbacks}{$channel}}, $callback;

        # Subscribe to Redis channel
        $self->{redis}->subscribe($channel, sub {
            my ($message, $channel) = @_;
            for my $cb (@{$self->{callbacks}{$channel}}) {
                $cb->($message);
            }
        });
    }

    sub publish ($self, $channel, $message) {
        $self->{redis}->publish($channel, encode_json($message));
    }

=head2 Alternative Backends

Consider these for production scaling:

=over 4

=item * B<Redis Pub/Sub> - Simple, widely supported

=item * B<PostgreSQL LISTEN/NOTIFY> - If already using PostgreSQL

=item * B<RabbitMQ> - Advanced routing and durability

=item * B<Apache Kafka> - High-throughput, persistent streams

=back

=head1 METHODS

=cut

# Singleton instance
my $instance;

=head2 instance

    my $pubsub = PAGI::Simple::PubSub->instance;

Returns the singleton PubSub instance. Creates it if it doesn't exist.

=cut

sub instance ($class) {
    return $instance //= $class->new;
}

=head2 reset

    PAGI::Simple::PubSub->reset;

Resets the singleton instance. Primarily useful for testing.

=cut

sub reset ($class) {
    $instance = undef;
}

=head2 new

    my $pubsub = PAGI::Simple::PubSub->new;

Creates a new PubSub instance. Normally you should use C<instance()>
instead to get the shared singleton.

=cut

sub new ($class) {
    my $self = bless {
        channels => {},  # channel => { callback_id => callback }
    }, $class;
    return $self;
}

=head2 subscribe

    $pubsub->subscribe($channel, $callback);

Subscribe to a channel. The callback will be called with the message
whenever something is published to the channel.

The callback receives a single argument: the message (which can be
any scalar, hashref, or arrayref).

Returns the pubsub instance for chaining.

=cut

sub subscribe ($self, $channel, $callback) {
    $self->{channels}{$channel} //= {};

    # Use refaddr as key to allow same callback to subscribe to multiple channels
    my $id = refaddr($callback);
    $self->{channels}{$channel}{$id} = $callback;

    return $self;
}

=head2 unsubscribe

    $pubsub->unsubscribe($channel, $callback);

Unsubscribe from a channel. The callback must be the same reference
that was passed to subscribe().

Returns the pubsub instance for chaining.

=cut

sub unsubscribe ($self, $channel, $callback) {
    return $self unless exists $self->{channels}{$channel};

    my $id = refaddr($callback);
    delete $self->{channels}{$channel}{$id};

    # Clean up empty channels
    if (!keys %{$self->{channels}{$channel}}) {
        delete $self->{channels}{$channel};
    }

    return $self;
}

=head2 unsubscribe_all

    $pubsub->unsubscribe_all($callback);

Unsubscribe a callback from all channels. Useful for cleanup when
a connection is closed.

Returns the pubsub instance for chaining.

=cut

sub unsubscribe_all ($self, $callback) {
    my $id = refaddr($callback);

    for my $channel (keys %{$self->{channels}}) {
        delete $self->{channels}{$channel}{$id};

        # Clean up empty channels
        if (!keys %{$self->{channels}{$channel}}) {
            delete $self->{channels}{$channel};
        }
    }

    return $self;
}

=head2 publish

    $pubsub->publish($channel, $message);

Publish a message to all subscribers of a channel.

The message can be any Perl value (scalar, hashref, arrayref).
Each subscriber callback receives the message as its argument.

Returns the number of subscribers that received the message.

=cut

sub publish ($self, $channel, $message) {
    return 0 unless exists $self->{channels}{$channel};

    my $callbacks = $self->{channels}{$channel};
    my $count = 0;

    for my $id (keys %$callbacks) {
        my $callback = $callbacks->{$id};
        if ($callback) {
            eval { $callback->($message) };
            if ($@) {
                warn "Error in pubsub callback: $@";
            }
            $count++;
        }
    }

    return $count;
}

=head2 subscribers

    my $count = $pubsub->subscribers($channel);

Returns the number of subscribers to a channel.

=cut

sub subscribers ($self, $channel) {
    return 0 unless exists $self->{channels}{$channel};
    return scalar keys %{$self->{channels}{$channel}};
}

=head2 channels

    my @channels = $pubsub->channels;

Returns a list of all active channels (channels with at least one subscriber).

=cut

sub channels ($self) {
    return keys %{$self->{channels}};
}

=head2 has_channel

    if ($pubsub->has_channel($channel)) { ... }

Returns true if the channel has any subscribers.

=cut

sub has_channel ($self, $channel) {
    return exists $self->{channels}{$channel}
        && keys %{$self->{channels}{$channel}} > 0;
}

=head1 SEE ALSO

L<PAGI::Simple>, L<PAGI::Simple::WebSocket>, L<PAGI::Simple::SSE>

=head1 AUTHOR

PAGI Contributors

=cut

1;
