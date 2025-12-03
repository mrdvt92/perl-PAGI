package PAGI::Simple::WebSocket;

use strict;
use warnings;
use experimental 'signatures';

our $VERSION = '0.01';

use Future::AsyncAwait;
use Scalar::Util qw(blessed refaddr);
use PAGI::Simple::PubSub;

=head1 NAME

PAGI::Simple::WebSocket - WebSocket context for PAGI::Simple

=head1 SYNOPSIS

    $app->websocket('/ws' => sub ($ws) {
        $ws->send("Welcome!");

        $ws->on(message => sub ($data) {
            $ws->send("Echo: $data");
        });

        $ws->on(close => sub {
            # Cleanup
        });
    });

=head1 DESCRIPTION

PAGI::Simple::WebSocket provides a context object for handling WebSocket
connections. It wraps the low-level PAGI WebSocket protocol with a
convenient callback-based API.

=head1 COMPLETE EXAMPLES

=head2 Room-Based Chat Application

A full-featured chat room implementation with user management:

    $app->websocket('/chat/:room' => sub ($ws) {
        my $room = $ws->path_params->{room};
        my $channel = "chat:room:$room";
        my $user = { name => 'Guest_' . int(rand(10000)) };

        # Join the chat room
        $ws->join($channel);

        # Notify others of new user
        $ws->broadcast_others($channel, {
            type => 'user_joined',
            user => $user->{name},
            timestamp => time(),
        });

        # Handle incoming messages
        $ws->on(message => sub ($data) {
            my $msg;
            eval { $msg = decode_json($data) };
            return if $@;  # Invalid JSON

            if ($msg->{type} eq 'set_name') {
                my $old_name = $user->{name};
                $user->{name} = $msg->{name} =~ s/[^\w\s-]//gr;  # Sanitize
                $ws->broadcast($channel, {
                    type => 'name_changed',
                    old_name => $old_name,
                    new_name => $user->{name},
                });
            }
            elsif ($msg->{type} eq 'message') {
                $ws->broadcast($channel, {
                    type => 'message',
                    user => $user->{name},
                    text => $msg->{text},
                    timestamp => time(),
                });
            }
            elsif ($msg->{type} eq 'typing') {
                $ws->broadcast_others($channel, {
                    type => 'typing',
                    user => $user->{name},
                });
            }
        });

        # Handle disconnection
        $ws->on(close => sub {
            $ws->broadcast_others($channel, {
                type => 'user_left',
                user => $user->{name},
                timestamp => time(),
            });
        });

        # Send welcome message
        $ws->send(encode_json({
            type => 'welcome',
            room => $room,
            your_name => $user->{name},
        }));
    });

=head2 Binary Message Handling

WebSocket supports both text and binary frames. Use binary for
images, files, or any non-text data:

    $app->websocket('/upload' => sub ($ws) {
        my $file_buffer = '';
        my $file_meta = {};

        $ws->on(message => sub ($data) {
            # Check if it looks like JSON (text message with metadata)
            if ($data =~ /^\{/) {
                my $meta = decode_json($data);
                if ($meta->{type} eq 'file_start') {
                    $file_buffer = '';
                    $file_meta = {
                        name => $meta->{name},
                        size => $meta->{size},
                        type => $meta->{mime_type},
                    };
                    $ws->send('{"status":"ready"}');
                }
                elsif ($meta->{type} eq 'file_complete') {
                    # Process the complete file
                    save_file($file_meta->{name}, $file_buffer);
                    $ws->send('{"status":"saved"}');
                }
            }
            else {
                # Binary data - append to buffer
                $file_buffer .= $data;
            }
        });
    });

    # Sending binary data to client
    $app->websocket('/download/:file' => sub ($ws) {
        my $file = $ws->path_params->{file};

        # Send file metadata first
        $ws->send(encode_json({
            type => 'file_meta',
            name => $file,
            size => -s "/files/$file",
        }));

        # Send file contents as binary
        open my $fh, '<:raw', "/files/$file" or return;
        while (read($fh, my $chunk, 65536)) {
            $ws->send($chunk, binary => 1);
        }
        close $fh;

        $ws->send('{"type":"complete"}');
    });

=head2 Error Handling Patterns

Robust error handling for production applications:

    $app->websocket('/api' => sub ($ws) {
        # Register error handler first
        $ws->on(error => sub ($error) {
            warn "WebSocket error for client: $error";

            # Try to notify client if connection is still open
            unless ($ws->is_closed) {
                $ws->send(encode_json({
                    type => 'error',
                    message => 'An error occurred processing your request',
                }));
            }
        });

        $ws->on(message => sub ($data) {
            my $request;
            eval {
                $request = decode_json($data);
            };
            if ($@) {
                $ws->send(encode_json({
                    type => 'error',
                    message => 'Invalid JSON',
                }));
                return;
            }

            # Wrap business logic in eval
            eval {
                my $result = process_request($request);
                $ws->send(encode_json({
                    type => 'response',
                    id => $request->{id},
                    data => $result,
                }));
            };
            if ($@) {
                $ws->send(encode_json({
                    type => 'error',
                    id => $request->{id},
                    message => "Processing failed: $@",
                }));
            }
        });
    });

=head2 Heartbeat/Keepalive Pattern

Detect stale connections and keep proxies from closing idle connections:

    $app->websocket('/realtime' => sub ($ws) {
        my $last_pong = time();
        my $ping_interval = 30;  # seconds
        my $timeout = 90;  # seconds without pong = dead

        # Note: This is a conceptual example. In practice, you'd
        # integrate with an event loop timer (e.g., IO::Async timer)

        # Client should send pong responses
        $ws->on(message => sub ($data) {
            my $msg = eval { decode_json($data) };
            return unless $msg;

            if ($msg->{type} eq 'pong') {
                $last_pong = time();
                return;
            }

            # Handle other message types...
        });

        # Check for stale connection periodically
        # (integrate with your event loop)
        my $check_alive = sub {
            if (time() - $last_pong > $timeout) {
                warn "WebSocket client timed out";
                $ws->close(4000, "Connection timeout");
                return;
            }

            # Send ping
            $ws->send(encode_json({ type => 'ping', time => time() }));
        };

        # ... set up timer to call $check_alive every $ping_interval
    });

=head2 Reconnection Strategy (Client-Side)

While reconnection is handled client-side, your server should
support stateless reconnection:

    # JavaScript client example:
    #
    # class ReconnectingWebSocket {
    #     constructor(url) {
    #         this.url = url;
    #         this.reconnectDelay = 1000;
    #         this.maxDelay = 30000;
    #         this.connect();
    #     }
    #
    #     connect() {
    #         this.ws = new WebSocket(this.url);
    #         this.ws.onopen = () => {
    #             this.reconnectDelay = 1000;  // Reset on success
    #             this.onopen?.();
    #         };
    #         this.ws.onclose = () => {
    #             setTimeout(() => this.connect(), this.reconnectDelay);
    #             this.reconnectDelay = Math.min(
    #                 this.reconnectDelay * 2,
    #                 this.maxDelay
    #             );
    #         };
    #     }
    # }

    # Server should handle reconnection gracefully:
    $app->websocket('/stream/:session_id' => sub ($ws) {
        my $session_id = $ws->path_params->{session_id};

        # Restore session state if exists
        my $session = get_session($session_id) // {
            created => time(),
            last_event_id => 0,
        };

        # Send any missed events since last connection
        if ($session->{last_event_id}) {
            my @missed = get_events_since($session->{last_event_id});
            for my $event (@missed) {
                $ws->send(encode_json($event));
            }
        }

        $ws->on(message => sub ($data) {
            my $msg = decode_json($data);
            if ($msg->{type} eq 'ack') {
                $session->{last_event_id} = $msg->{event_id};
                save_session($session_id, $session);
            }
        });
    });

=head1 CLOSE CODES

Standard WebSocket close codes you may encounter or use:

=over 4

=item * B<1000> - Normal closure

=item * B<1001> - Going away (page navigation, server shutdown)

=item * B<1002> - Protocol error

=item * B<1003> - Unsupported data type

=item * B<1008> - Policy violation

=item * B<1011> - Unexpected condition (server error)

=item * B<4000-4999> - Application-specific codes

=back

    # Examples
    $ws->close(1000, "Goodbye");           # Normal close
    $ws->close(1008, "Unauthorized");      # Policy violation
    $ws->close(4001, "Invalid session");   # Custom app code

=head1 METHODS

=cut

=head2 new

    my $ws = PAGI::Simple::WebSocket->new(
        app         => $app,
        scope       => $scope,
        receive     => $receive,
        send        => $send,
        path_params => \%params,
    );

Create a new WebSocket context.

=cut

sub new ($class, %args) {
    my $self = bless {
        app         => $args{app},
        scope       => $args{scope},
        receive     => $args{receive},
        send        => $args{send},
        path_params => $args{path_params} // {},
        stash       => {},
        _handlers   => {
            message => [],
            close   => [],
            error   => [],
        },
        _accepted   => 0,
        _closed     => 0,
        _rooms      => {},  # channel => 1 for tracking joined rooms
        _pubsub_cb  => undef,  # Callback for receiving broadcast messages
    }, $class;

    # Create the pubsub callback for this connection
    $self->{_pubsub_cb} = sub ($message) {
        # Send the message to this client
        $self->send($message) unless $self->{_closed};
    };

    return $self;
}

=head2 app

    my $app = $ws->app;

Returns the PAGI::Simple application instance.

=cut

sub app ($self) {
    return $self->{app};
}

=head2 scope

    my $scope = $ws->scope;

Returns the raw PAGI scope hashref.

=cut

sub scope ($self) {
    return $self->{scope};
}

=head2 stash

    my $stash = $ws->stash;
    $ws->stash->{user} = $user;

Per-connection storage hashref.

=cut

sub stash ($self) {
    return $self->{stash};
}

=head2 path_params

    my $params = $ws->path_params;

Returns the path parameters captured from the route.

=cut

sub path_params ($self) {
    return $self->{path_params};
}

=head2 param

    my $value = $ws->param('id');

Get a path parameter by name.

=cut

sub param ($self, $name) {
    return $self->{path_params}{$name};
}

=head2 on

    $ws->on(message => sub ($data) { ... });
    $ws->on(close => sub { ... });
    $ws->on(error => sub ($error) { ... });

Register event handlers. Multiple handlers can be registered for each event.

Events:
- C<message>: Called when a message is received from the client
- C<close>: Called when the connection is closed
- C<error>: Called when an error occurs

=cut

sub on ($self, $event, $callback) {
    if (exists $self->{_handlers}{$event}) {
        push @{$self->{_handlers}{$event}}, $callback;
    }
    else {
        die "Unknown event type: $event (expected message, close, or error)";
    }
    return $self;
}

=head2 send

    await $ws->send("Hello");
    await $ws->send($binary_data, binary => 1);

Send a message to the client. Returns a Future.

Options:
- C<binary>: If true, send as binary frame (default: text)

=cut

async sub send ($self, $data, %opts) {
    return if $self->{_closed};

    my $type = $opts{binary} ? 'binary' : 'text';

    await $self->{send}->({
        type  => 'websocket.send',
        $type => $data,
    });
}

=head2 close

    await $ws->close;
    await $ws->close(1000);
    await $ws->close(1000, "Normal closure");

Close the WebSocket connection.

=cut

async sub close ($self, $code = 1000, $reason = '') {
    return if $self->{_closed};
    $self->{_closed} = 1;

    await $self->{send}->({
        type   => 'websocket.close',
        code   => $code,
        reason => $reason,
    });
}

=head2 is_closed

    if ($ws->is_closed) { ... }

Returns true if the connection has been closed.

=cut

sub is_closed ($self) {
    return $self->{_closed};
}

=head2 join

    $ws->join('room:general');

Join a room/channel. Messages broadcast to this room will be sent
to this connection.

Returns $self for chaining.

=cut

sub join ($self, $channel) {
    return $self if $self->{_rooms}{$channel};  # Already joined

    my $pubsub = PAGI::Simple::PubSub->instance;
    $pubsub->subscribe($channel, $self->{_pubsub_cb});
    $self->{_rooms}{$channel} = 1;

    return $self;
}

=head2 leave

    $ws->leave('room:general');

Leave a room/channel. Stops receiving broadcasts for this room.

Returns $self for chaining.

=cut

sub leave ($self, $channel) {
    return $self unless $self->{_rooms}{$channel};  # Not in room

    my $pubsub = PAGI::Simple::PubSub->instance;
    $pubsub->unsubscribe($channel, $self->{_pubsub_cb});
    delete $self->{_rooms}{$channel};

    return $self;
}

=head2 leave_all

    $ws->leave_all;

Leave all rooms. Called automatically on disconnect.

Returns $self for chaining.

=cut

sub leave_all ($self) {
    my $pubsub = PAGI::Simple::PubSub->instance;

    for my $channel (keys %{$self->{_rooms}}) {
        $pubsub->unsubscribe($channel, $self->{_pubsub_cb});
    }
    $self->{_rooms} = {};

    return $self;
}

=head2 rooms

    my @rooms = $ws->rooms;

Returns a list of rooms this connection has joined.

=cut

sub rooms ($self) {
    return keys %{$self->{_rooms}};
}

=head2 in_room

    if ($ws->in_room('room:general')) { ... }

Returns true if this connection is in the specified room.

=cut

sub in_room ($self, $channel) {
    return exists $self->{_rooms}{$channel};
}

=head2 broadcast

    $ws->broadcast('room:general', 'Hello everyone!');

Broadcast a message to all connections in a room, INCLUDING this connection.

Returns the number of connections that received the message.

=cut

sub broadcast ($self, $channel, $message) {
    my $pubsub = PAGI::Simple::PubSub->instance;
    return $pubsub->publish($channel, $message);
}

=head2 broadcast_others

    $ws->broadcast_others('room:general', 'Hello others!');

Broadcast a message to all connections in a room, EXCLUDING this connection.

Returns the number of connections that received the message (excluding self).

=cut

sub broadcast_others ($self, $channel, $message) {
    my $pubsub = PAGI::Simple::PubSub->instance;

    # Temporarily unsubscribe, publish, then resubscribe
    my $was_in_room = $self->{_rooms}{$channel};

    if ($was_in_room) {
        $pubsub->unsubscribe($channel, $self->{_pubsub_cb});
    }

    my $count = $pubsub->publish($channel, $message);

    if ($was_in_room) {
        $pubsub->subscribe($channel, $self->{_pubsub_cb});
    }

    return $count;
}

# Internal: Accept the WebSocket connection
async sub _accept ($self) {
    return if $self->{_accepted};
    $self->{_accepted} = 1;

    await $self->{send}->({
        type => 'websocket.accept',
    });
}

# Internal: Run the event loop for this connection
async sub _run ($self, $handler) {
    # First, receive the connect event
    my $connect = await $self->{receive}->();
    if ($connect->{type} ne 'websocket.connect') {
        # Unexpected event type
        await $self->close(4000, "Expected websocket.connect");
        return;
    }

    # Accept the connection
    await $self->_accept();

    # Call the user's handler to set up event callbacks
    my $result = $handler->($self);
    if (blessed($result) && $result->isa('Future')) {
        await $result;
    }

    # Enter the message loop
    while (!$self->{_closed}) {
        my $event = await $self->{receive}->();
        my $type = $event->{type} // '';

        if ($type eq 'websocket.receive') {
            # Got a message from the client
            my $data = $event->{text} // $event->{bytes};
            for my $cb (@{$self->{_handlers}{message}}) {
                eval {
                    my $r = $cb->($data);
                    if (blessed($r) && $r->isa('Future')) {
                        await $r;
                    }
                };
                if ($@) {
                    $self->_trigger_error($@);
                }
            }
        }
        elsif ($type eq 'websocket.disconnect') {
            # Client disconnected
            $self->{_closed} = 1;
            $self->_trigger_close();
            last;
        }
        elsif ($type eq 'websocket.close') {
            # Close requested (could be from client or server)
            $self->{_closed} = 1;
            $self->_trigger_close();
            last;
        }
    }
}

# Internal: Trigger close handlers
sub _trigger_close ($self) {
    # Auto-leave all rooms
    $self->leave_all;

    for my $cb (@{$self->{_handlers}{close}}) {
        eval { $cb->() };
        if ($@) {
            warn "Error in close handler: $@";
        }
    }
}

# Internal: Trigger error handlers
sub _trigger_error ($self, $error) {
    for my $cb (@{$self->{_handlers}{error}}) {
        eval { $cb->($error) };
    }
    # If no error handlers, warn
    if (!@{$self->{_handlers}{error}}) {
        warn "WebSocket error: $error";
    }
}

=head1 SEE ALSO

L<PAGI::Simple>, L<PAGI::Simple::Context>

=head1 AUTHOR

PAGI Contributors

=cut

1;
