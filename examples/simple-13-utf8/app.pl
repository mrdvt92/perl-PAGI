#!/usr/bin/env perl
use strict;
use warnings;
use utf8;
use experimental 'signatures';

use Encode qw(encode_utf8);
use Future::AsyncAwait;
use PAGI::Simple;

# Run with:
#   pagi-server --app examples/simple-13-utf8/app.pl --port 5000

my $app = PAGI::Simple->new(name => 'PAGI::Simple UTF-8 Demo');

my @samples = ('λ', '🔥', '中文', '♥', 'café');

$app->get('/' => async sub ($c) {
    my ($echo, $source) = await _extract_echo($c);
    await _render_page($c, $echo, $source);
});

$app->post('/' => async sub ($c) {
    my ($echo, $source) = await _extract_echo($c);
    await _render_page($c, $echo, $source);
});

$app->get('/echo/:text' => async sub ($c) {
    my $text = $c->path_params->{text};
    await _render_page($c, $text, 'path');
});

sub _render_page ($c, $echo, $source) {
    my $echo_section = '';

    if (defined $echo && length $echo) {
        my $chars       = length($echo);
        my $bytes       = length(encode_utf8($echo));
        my $codepoints  = join ' ', map { sprintf 'U+%04X', ord($_) } split //, $echo;
        my $safe_source = $source // 'unknown';

        $echo_section = <<"ECHO";
<div style="background: #e8f5e9; padding: 1em; margin: 1em 0; border-radius: 4px;">
  <h2>Echo (from $safe_source):</h2>
  <pre style="font-size: 1.5em;">$echo</pre>
  <p>Characters: $chars | UTF-8 bytes: $bytes</p>
  <p>Codepoints: $codepoints</p>
</div>
ECHO
    }

    my $path_links = join ' | ', map {
        my $encoded = _uri_encode($_);
        qq{<a href="/echo/$encoded">$_</a>};
    } @samples;

    my $html = <<"HTML";
<!DOCTYPE html>
<html><head><meta charset="UTF-8"><title>PAGI::Simple UTF-8</title></head>
<body>
<h1>PAGI::Simple UTF-8 Round-Trip Test</h1>
<p>Samples: λ (Greek) | 🔥 (Emoji) | 中文 (CJK) | ♥ (Symbol) | café (Accented)</p>

$echo_section

<h2>1. Path Test</h2>
<p>Click: $path_links</p>
<p><small>Tests decoded path params via \$c->path_params</small></p>

<h2>2. Query String Test</h2>
<form method="GET"  action="/">
  <input name="text" value="λ 🔥 中文" style="font-size: 1.2em;" />
  <button type="submit">GET</button>
</form>
<p><small>Tests \$c->req->query_param('text') (UTF-8 decoded with replacement)</small></p>

<h2>3. POST Body Test</h2>
<form method="POST"  action="/">
  <textarea name="text" rows="3" cols="40" style="font-size: 1.2em;">λ 🔥 中文 ♥ café</textarea><br>
  <button type="submit" style="margin-top: 0.5em;">POST</button>
</form>
<p><small>Tests form body via \$c->req->body_param('text') (UTF-8 decoded with replacement)</small></p>

</body></html>
HTML

    return $c->html($html);
}

async sub _extract_echo ($c) {
    if (defined(my $path_val = $c->path_params->{text})) {
        return ($path_val, 'path');
    }

    if (defined(my $query_val = $c->req->query_param('text'))) {
        return ($query_val, 'query string');
    }

    if (defined(my $body_val = await $c->req->body_param('text'))) {
        return ($body_val, 'POST body');
    }

    return (undef, undef);
}

sub _uri_encode ($str) {
    my $bytes = encode_utf8($str);
    $bytes =~ s/([^A-Za-z0-9\-._~])/sprintf("%%%02X", ord($1))/eg;
    return $bytes;
}

$app->to_app;
