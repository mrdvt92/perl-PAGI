package Test::PAGI::Server;
use strict;
use warnings;
use experimental 'signatures';

our $VERSION = '0.001';

=head1 NAME

Test::PAGI::Server - Test utilities for PAGI::Server

=head1 SYNOPSIS

    use Test::PAGI::Server;

    my $test = Test::PAGI::Server->new(app => \&app);
    $test->start;

    my $response = $test->request(GET => '/');
    is($response->code, 200);

    $test->stop;

=head1 DESCRIPTION

Test utilities for running integration tests against PAGI::Server.

=cut

sub new ($class, %args) {
    my $self = bless {
        app  => $args{app},
        port => $args{port} // 0,  # 0 = pick available port
    }, $class;
    return $self;
}

sub start ($self) {
    # TODO: Implement - start server in background
}

sub stop ($self) {
    # TODO: Implement - stop server
}

sub port ($self) {
    return $self->{port};
}

sub base_url ($self) {
    return "http://127.0.0.1:" . $self->port;
}

sub request ($self, $method, $path, %opts) {
    # TODO: Implement - make HTTP request
}

sub websocket ($self, $path, %opts) {
    # TODO: Implement - open WebSocket connection
}

1;

__END__

=head1 AUTHOR

John Napiorkowski E<lt>jjnapiork@cpan.orgE<gt>

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
