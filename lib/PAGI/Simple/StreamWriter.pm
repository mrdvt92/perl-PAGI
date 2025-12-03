package PAGI::Simple::StreamWriter;

use strict;
use warnings;
use experimental 'signatures';

our $VERSION = '0.01';

use Future::AsyncAwait;

=head1 NAME

PAGI::Simple::StreamWriter - Streaming response writer for PAGI::Simple

=head1 SYNOPSIS

    $app->get('/stream' => sub ($c) {
        await $c->stream(async sub ($writer) {
            await $writer->write("Starting...\n");
            for my $i (1..10) {
                await $writer->write("Chunk $i\n");
            }
            await $writer->close;
        });
    });

=head1 DESCRIPTION

PAGI::Simple::StreamWriter provides a convenient interface for streaming
chunked responses. It wraps the low-level PAGI send interface and manages
the chunked transfer encoding automatically.

=head1 METHODS

=cut

=head2 new

    my $writer = PAGI::Simple::StreamWriter->new($context, %opts);

Create a new stream writer. This is called internally by C<< $c->stream() >>.

=cut

sub new ($class, $context, %opts) {
    my $self = bless {
        context    => $context,
        send       => $context->send,
        closed     => 0,
        bytes_sent => 0,
    }, $class;

    return $self;
}

=head2 write

    await $writer->write($data);
    await $writer->write("chunk 1");
    await $writer->write($binary_data);

Write a chunk of data to the stream. This method is async and should be awaited.

Returns the writer for chaining.

Throws an exception if the stream has already been closed.

=cut

async sub write ($self, $data) {
    die "Stream already closed" if $self->{closed};

    my $body = defined $data ? "$data" : '';
    $self->{bytes_sent} += length($body);

    await $self->{send}->({
        type => 'http.response.body',
        body => $body,
        more => 1,  # More chunks to come
    });

    return $self;
}

=head2 writeln

    await $writer->writeln("line of text");

Write a line of data (with newline) to the stream. Convenience method
that appends "\n" to the data.

Returns the writer for chaining.

=cut

async sub writeln ($self, $data) {
    return await $self->write("$data\n");
}

=head2 close

    await $writer->close;

Close the stream by sending the final (empty) chunk. This signals
to the client that the response is complete.

This method is idempotent - calling it multiple times has no effect.

=cut

async sub close ($self) {
    return if $self->{closed};

    $self->{closed} = 1;

    await $self->{send}->({
        type => 'http.response.body',
        body => '',
        more => 0,  # Final chunk
    });

    return $self;
}

=head2 is_closed

    if ($writer->is_closed) { ... }

Returns true if the stream has been closed.

=cut

sub is_closed ($self) {
    return $self->{closed};
}

=head2 bytes_sent

    my $total = $writer->bytes_sent;

Returns the total number of bytes sent so far.

=cut

sub bytes_sent ($self) {
    return $self->{bytes_sent};
}

=head1 EXAMPLE

    $app->get('/countdown' => sub ($c) {
        await $c->stream(async sub ($writer) {
            my $loop = IO::Async::Loop->new;

            for my $i (reverse 1..10) {
                await $writer->writeln("$i...");
                await $loop->delay_future(after => 1);
            }

            await $writer->writeln("Liftoff!");
            await $writer->close;
        }, content_type => 'text/plain');
    });

=head1 SEE ALSO

L<PAGI::Simple::Context>, L<PAGI::Simple>

=head1 AUTHOR

PAGI Contributors

=cut

1;
