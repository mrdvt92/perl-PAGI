#!/usr/bin/env perl
use strict;
use warnings;
use experimental 'signatures';
use utf8;

# PAGI::Simple Views Example
# Run with: pagi-server --app examples/simple-15-views/app.pl --port 5000

use PAGI::Simple;

# Create app with views configured in constructor
# Relative paths are resolved from the directory containing this file
my $app = PAGI::Simple->new(
    name  => 'Views Demo',
    views => 'templates',  # Same as views => { directory => 'templates' }
);

# Home page - renders index.html.ep with layout
$app->get('/' => sub ($c) {
    $c->render('index',
        title => 'Welcome',
        message => 'Hello from PAGI::Simple Views λ 🔥 中文 ♥!',
    );
});

# Greet by name - demonstrates variable interpolation
$app->get('/greet/:name' => sub ($c) {
    my $name = $c->path_params->{name};
    $c->render('greet',
        title => "Hello $name",
        name => $name,
    );
});

# Page without layout - uses render_string for inline template
$app->get('/fragment' => sub ($c) {
    my $html = $c->render_string('<p>Just a fragment: <%= $v->{msg} %></p>',
        msg => 'No layout here!'
    );
    $c->html($html);
});

# Demonstrates include (partial)
$app->get('/with-partial' => sub ($c) {
    $c->render('with_partial',
        title => 'Partial Demo',
        items => ['Apple', 'Banana', 'Cherry'],
    );
});

# Return the PAGI app
$app->to_app;
