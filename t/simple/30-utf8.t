use strict;
use warnings;
use experimental 'signatures';
use Test2::V0;
use Future;
use Future::AsyncAwait;
use Encode qw(encode_utf8 decode_utf8);
use JSON::MaybeXS;

use PAGI::Simple;

# Helpers
sub percent_encode ($str) {
    my $bytes = encode_utf8($str // '');
    $bytes =~ s/([^A-Za-z0-9\-._~])/sprintf("%%%02X", ord($1))/eg;
    return $bytes;
}

sub simulate_http ($app, %opts) {
    my $method  = $opts{method}       // 'GET';
    my $path    = $opts{path}         // '/';
    my $query   = $opts{query_string} // '';
    my $body    = $opts{body}         // '';
    my $headers = $opts{headers}      // [];

    my @sent;
    my $scope = {
        type         => 'http',
        method       => $method,
        path         => $path,
        query_string => $query,
        headers      => $headers,
    };

    my $receive = sub { Future->done({ type => 'http.request', body => $body, more => 0 }) };
    my $send    = sub ($event) { push @sent, $event; Future->done };

    my $pagi_app = $app->to_app;
    $pagi_app->($scope, $receive, $send)->get;

    return \@sent;
}

sub simulate_websocket ($app, %opts) {
    my $path     = $opts{path}     // '/ws';
    my $messages = $opts{messages} // [];

    my @sent;
    my @events = ({ type => 'websocket.connect' });
    push @events, map { { type => 'websocket.receive', text => $_ } } @$messages;
    push @events, { type => 'websocket.disconnect' };

    my $receive = sub {
        return Future->done(shift(@events) // { type => 'websocket.disconnect' });
    };
    my $send = sub ($event) { push @sent, $event; Future->done };

    my $pagi_app = $app->to_app;
    $pagi_app->({ type => 'websocket', path => $path }, $receive, $send)->get;

    return \@sent;
}

my $sample = "\x{03BB}\x{1F525}caf\x{E9}";  # lambda + fire + café
my $json   = JSON::MaybeXS->new(utf8 => 1);

# Test 1: Path, query, and body UTF-8 round trip with response encoding
subtest 'HTTP UTF-8 round trip' => sub {
    my $app = PAGI::Simple->new;

    $app->post('/utf8/:path_text' => async sub ($c) {
        my $path  = $c->path_params->{path_text};
        my $query = $c->req->query_param('text');
        my $body  = await $c->req->body_param('text');
        $c->json({ path => $path, query => $query, body => $body });
    });

    my $encoded = percent_encode($sample);
    my $sent = simulate_http(
        $app,
        method       => 'POST',
        path         => "/utf8/$sample",
        query_string => "text=$encoded",
        body         => "text=$encoded",
        headers      => [['content-type', 'application/x-www-form-urlencoded']],
    );

    is($sent->[0]{status}, 200, 'status 200');

    my @ct = grep { $_->[0] eq 'content-type' } @{$sent->[0]{headers}};
    like($ct[0][1], qr/charset=utf-8/i, 'content-type has utf-8 charset');

    my $body = $sent->[1]{body};
    my @cl = grep { lc($_->[0]) eq 'content-length' } @{$sent->[0]{headers}};
    is($cl[0][1], length($body), 'content-length matches encoded bytes');

    my $decoded = $json->decode($body);
    is($decoded->{path},  $sample, 'path param decoded');
    is($decoded->{query}, $sample, 'query param decoded');
    is($decoded->{body},  $sample, 'body param decoded');
};

# Test 2: Invalid UTF-8 replaced by default; raw and strict exposed
subtest 'UTF-8 replacement, raw, and strict' => sub {
    my $app = PAGI::Simple->new;

    $app->post('/invalid' => async sub ($c) {
        my $decoded_q = $c->req->query_param('text');
        my $raw_q     = $c->req->raw_query_param('text');
        my $decoded_b = await $c->req->body_param('text');
        my $raw_b     = await $c->req->raw_body_param('text');

        my $strict_q_ok = eval { $c->req->query_param('text', strict => 1); 1 } ? 1 : 0;
        my $strict_b_ok = eval { await $c->req->body_param('text', strict => 1); 1 } ? 1 : 0;

        $c->json({
            decoded_q => $decoded_q,
            raw_q_hex => defined $raw_q ? unpack('H*', $raw_q) : undef,
            decoded_b => $decoded_b,
            raw_b_hex => defined $raw_b ? unpack('H*', $raw_b) : undef,
            strict_q_ok => $strict_q_ok,
            strict_b_ok => $strict_b_ok,
        });
    });

    my $sent = simulate_http(
        $app,
        method       => 'POST',
        path         => '/invalid',
        query_string => 'text=%FF',
        body         => 'text=%FF',
        headers      => [['content-type', 'application/x-www-form-urlencoded']],
    );

    my $decoded = $json->decode($sent->[1]{body});

    is($decoded->{decoded_q}, "\x{FFFD}", 'query replaced invalid byte');
    is($decoded->{decoded_b}, "\x{FFFD}", 'body replaced invalid byte');
    is($decoded->{raw_q_hex}, 'ff', 'raw query preserved bytes');
    is($decoded->{raw_b_hex}, 'ff', 'raw body preserved bytes');
    is($decoded->{strict_q_ok}, 0, 'strict query decoding croaks');
    is($decoded->{strict_b_ok}, 0, 'strict body decoding croaks');
};

# Test 3: Response helpers encode UTF-8 and set lengths
subtest 'response helpers encode UTF-8' => sub {
    my $app = PAGI::Simple->new;

    $app->get('/text' => sub ($c) { $c->text($sample) });
    my $sent_text = simulate_http($app, path => '/text');
    my $text_body = $sent_text->[1]{body};
    is(decode_utf8($text_body), $sample, 'text body matches sample');
    my @text_len = grep { lc($_->[0]) eq 'content-length' } @{$sent_text->[0]{headers}};
    is($text_len[0][1], length($text_body), 'text content-length matches bytes');

    $app->get('/html' => sub ($c) { $c->html("<p>$sample</p>") });
    my $sent_html = simulate_http($app, path => '/html');
    my $html_body = $sent_html->[1]{body};
    like(decode_utf8($html_body), qr/\Q$sample\E/, 'html body contains sample');
    my @html_len = grep { lc($_->[0]) eq 'content-length' } @{$sent_html->[0]{headers}};
    is($html_len[0][1], length($html_body), 'html content-length matches bytes');
};

# Test 4: WebSocket UTF-8 path params and messages
subtest 'WebSocket UTF-8 path and messages' => sub {
    my $app = PAGI::Simple->new;

    $app->websocket('/chat/:room' => sub ($ws) {
        my $room = $ws->path_params->{room};
        $ws->send("welcome:$room");
        $ws->on(message => sub ($data) {
            $ws->send("echo:$room:$data");
        });
    });

    my $sent = simulate_websocket($app,
        path     => "/chat/$sample",
        messages => ["msg:$sample"],
    );

    my @accept = grep { $_->{type} eq 'websocket.accept' } @$sent;
    is(scalar @accept, 1, 'connection accepted');

    my @sends = grep { $_->{type} eq 'websocket.send' } @$sent;
    is($sends[0]{text}, "welcome:$sample", 'welcome includes UTF-8 path param');
    is($sends[1]{text}, "echo:$sample:msg:$sample", 'echo includes UTF-8 message and path');
};

done_testing;
