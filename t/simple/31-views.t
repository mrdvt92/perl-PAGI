#!/usr/bin/env perl
use strict;
use warnings;
use Test2::V0;
use File::Temp qw(tempdir);
use File::Path qw(make_path);

use lib 'lib';

# Test that we can integrate views with PAGI::Simple and Context
use PAGI::Simple;
use PAGI::Simple::View;
use PAGI::Simple::Context;
use PAGI::Simple::Request;

# Create temp directory for templates
my $tmpdir = tempdir(CLEANUP => 1);

# Create templates directory structure
make_path("$tmpdir/templates");
make_path("$tmpdir/templates/layouts");
make_path("$tmpdir/templates/todos");

# Create layout template
open my $fh1, '>', "$tmpdir/templates/layouts/default.html.ep" or die $!;
print $fh1 <<'LAYOUT';
<!DOCTYPE html>
<html>
<head><title><%= $v->{title} // 'App' %></title></head>
<body>
<%= content() %>
</body>
</html>
LAYOUT
close $fh1;

# Create simple template without layout
open my $fh2, '>', "$tmpdir/templates/simple.html.ep" or die $!;
print $fh2 '<h1>Hello, <%= $v->{name} %>!</h1>';
close $fh2;

# Create template with layout
open my $fh3, '>', "$tmpdir/templates/with_layout.html.ep" or die $!;
print $fh3 <<'TEMPLATE';
<% extends('layouts/default', title => 'Home') %>
<main>
<h1>Welcome, <%= $v->{name} %>!</h1>
</main>
TEMPLATE
close $fh3;

# Create partial
open my $fh4, '>', "$tmpdir/templates/todos/_item.html.ep" or die $!;
print $fh4 '<li class="todo"><%= $v->{todo}{title} %></li>';
close $fh4;

# Create template with include
open my $fh5, '>', "$tmpdir/templates/with_include.html.ep" or die $!;
print $fh5 <<'TEMPLATE';
<ul>
<%= include('todos/_item', todo => $v->{todo}) %>
</ul>
TEMPLATE
close $fh5;

#-------------------------------------------------------------------------
# Test 1: views() method on PAGI::Simple
#-------------------------------------------------------------------------
subtest 'views() configuration method on PAGI::Simple' => sub {
    my $app = PAGI::Simple->new;

    ok(!$app->view, 'No view before calling views()');

    my $result = $app->views("$tmpdir/templates", {
        auto_escape => 1,
        cache       => 0,
    });

    ok($result == $app, 'views() returns $app for chaining');
    ok($app->view, 'view() returns View instance after views()');
    ok(ref($app->view) eq 'PAGI::Simple::View', 'view() is a PAGI::Simple::View');

    is($app->view->template_dir, "$tmpdir/templates", 'template_dir set correctly');
    is($app->view->extension, '.html.ep', 'extension defaults to .html.ep');
};

#-------------------------------------------------------------------------
# Test 1b: views option in constructor (shorthand string)
#-------------------------------------------------------------------------
subtest 'views option in constructor (shorthand string)' => sub {
    my $app = PAGI::Simple->new(
        name  => 'Test App',
        views => "$tmpdir/templates",
    );

    ok($app->view, 'view() is set when views passed to constructor');
    is(ref($app->view), 'PAGI::Simple::View', 'view is a View instance');
    is($app->view->template_dir, "$tmpdir/templates", 'template_dir from constructor');

    my $output = $app->view->render('simple', name => 'Constructor');
    like($output, qr/<h1>Hello, Constructor!<\/h1>/, 'Rendering works with constructor views');
};

#-------------------------------------------------------------------------
# Test 1c: views option in constructor (hashref with options)
#-------------------------------------------------------------------------
subtest 'views option in constructor (hashref with options)' => sub {
    my $app = PAGI::Simple->new(
        name  => 'Test App',
        views => {
            directory => "$tmpdir/templates",
            cache     => 0,
        },
    );

    ok($app->view, 'view() is set with hashref views option');
    is($app->view->template_dir, "$tmpdir/templates", 'template_dir from hashref');

    my $output = $app->view->render('simple', name => 'Hashref');
    like($output, qr/<h1>Hello, Hashref!<\/h1>/, 'Rendering works with hashref views');
};

#-------------------------------------------------------------------------
# Test 1d: views() method overrides constructor config
#-------------------------------------------------------------------------
subtest 'views() method overrides constructor config' => sub {
    # Create alternate templates directory
    make_path("$tmpdir/alt_templates");
    open my $fh, '>', "$tmpdir/alt_templates/simple.html.ep" or die $!;
    print $fh '<h2>Alt: <%= $v->{name} %></h2>';
    close $fh;

    my $app = PAGI::Simple->new(
        name  => 'Test App',
        views => "$tmpdir/templates",
    );

    # Initially uses constructor config
    my $output1 = $app->view->render('simple', name => 'First');
    like($output1, qr/<h1>Hello, First!<\/h1>/, 'Initially uses constructor views');

    # Override with views() method
    $app->views("$tmpdir/alt_templates");

    my $output2 = $app->view->render('simple', name => 'Second');
    like($output2, qr/<h2>Alt: Second<\/h2>/, 'views() method overrides constructor');
};

#-------------------------------------------------------------------------
# Test 1e: views() with flat options syntax
#-------------------------------------------------------------------------
subtest 'views() with flat options syntax' => sub {
    my $app = PAGI::Simple->new;

    $app->views("$tmpdir/templates", cache => 0, auto_escape => 1);

    ok($app->view, 'view() is set with flat options');
    is($app->view->template_dir, "$tmpdir/templates", 'template_dir correct');

    my $output = $app->view->render('simple', name => 'Flat');
    like($output, qr/<h1>Hello, Flat!<\/h1>/, 'Rendering works with flat options');
};

#-------------------------------------------------------------------------
# Test 2: View renders templates correctly
#-------------------------------------------------------------------------
subtest 'View renders templates with variables' => sub {
    my $app = PAGI::Simple->new;
    $app->views("$tmpdir/templates", { cache => 0 });

    my $view = $app->view;

    my $output = $view->render('simple', name => 'World');
    like($output, qr/<h1>Hello, World!<\/h1>/, 'Template rendered with variable');
};

#-------------------------------------------------------------------------
# Test 3: View includes work
#-------------------------------------------------------------------------
subtest 'View includes partials' => sub {
    my $app = PAGI::Simple->new;
    $app->views("$tmpdir/templates", { cache => 0 });

    my $output = $app->view->render('with_include', todo => { title => 'Test Todo' });
    like($output, qr/<ul>/, 'Main template rendered');
    like($output, qr/<li class="todo">Test Todo<\/li>/, 'Partial included with variable');
};

#-------------------------------------------------------------------------
# Test 4: Layout system works
#-------------------------------------------------------------------------
subtest 'Layout system with extends' => sub {
    my $app = PAGI::Simple->new;
    $app->views("$tmpdir/templates", { cache => 0 });

    my $output = $app->view->render('with_layout', name => 'User');

    like($output, qr/<!DOCTYPE html>/, 'Layout rendered');
    like($output, qr/<title>Home<\/title>/, 'Title from extends vars');
    like($output, qr/<h1>Welcome, User!<\/h1>/, 'Content rendered in layout');
    like($output, qr/<body>.*<main>.*<\/main>.*<\/body>/s, 'Content in body');
};

#-------------------------------------------------------------------------
# Test 5: is_htmx detection
#-------------------------------------------------------------------------
subtest 'is_htmx request detection' => sub {
    # Create a mock scope without HX-Request header
    my $scope_normal = {
        type    => 'http',
        method  => 'GET',
        path    => '/',
        headers => [],
    };

    my $req_normal = PAGI::Simple::Request->new($scope_normal, sub {});
    ok(!$req_normal->is_htmx, 'Normal request is not htmx');

    # Create a mock scope WITH HX-Request header
    my $scope_htmx = {
        type    => 'http',
        method  => 'GET',
        path    => '/',
        headers => [
            ['hx-request', 'true'],
            ['hx-target', '#main'],
            ['hx-current-url', 'http://localhost/'],
        ],
    };

    my $req_htmx = PAGI::Simple::Request->new($scope_htmx, sub {});
    ok($req_htmx->is_htmx, 'Request with HX-Request header is htmx');
    is($req_htmx->htmx_target, '#main', 'htmx_target returns header value');
    is($req_htmx->htmx_current_url, 'http://localhost/', 'htmx_current_url returns header value');
};

#-------------------------------------------------------------------------
# Test 6: htmx header accessors
#-------------------------------------------------------------------------
subtest 'htmx request header accessors' => sub {
    my $scope = {
        type    => 'http',
        method  => 'POST',
        path    => '/form',
        headers => [
            ['hx-request', 'true'],
            ['hx-target', '#result'],
            ['hx-trigger', 'form-submit'],
            ['hx-trigger-name', 'saveButton'],
            ['hx-prompt', 'user input'],
            ['hx-boosted', 'true'],
        ],
    };

    my $req = PAGI::Simple::Request->new($scope, sub {});

    ok($req->is_htmx, 'is_htmx');
    is($req->htmx_target, '#result', 'htmx_target');
    is($req->htmx_trigger, 'form-submit', 'htmx_trigger');
    is($req->htmx_trigger_name, 'saveButton', 'htmx_trigger_name');
    is($req->htmx_prompt, 'user input', 'htmx_prompt');
    ok($req->htmx_boosted, 'htmx_boosted');
};

#-------------------------------------------------------------------------
# Test 7: Auto-escaping in templates
#-------------------------------------------------------------------------
subtest 'Auto-escaping prevents XSS' => sub {
    my $app = PAGI::Simple->new;
    $app->views("$tmpdir/templates", { auto_escape => 1, cache => 0 });

    my $output = $app->view->render('simple', name => '<script>alert(1)</script>');
    like($output, qr/&lt;script&gt;/, 'Script tag escaped');
    unlike($output, qr/<script>alert/, 'Raw script NOT present');
};

#-------------------------------------------------------------------------
# Test 8: raw() helper in templates
#-------------------------------------------------------------------------
subtest 'raw() helper bypasses escaping' => sub {
    # Create a template using raw()
    open my $fh, '>', "$tmpdir/templates/raw_test.html.ep" or die $!;
    print $fh '<div><%= raw($v->{html}) %></div>';
    close $fh;

    my $app = PAGI::Simple->new;
    $app->views("$tmpdir/templates", { auto_escape => 1, cache => 0 });

    my $output = $app->view->render('raw_test', html => '<b>bold</b>');
    like($output, qr/<b>bold<\/b>/, 'Raw HTML preserved');
};

done_testing;
