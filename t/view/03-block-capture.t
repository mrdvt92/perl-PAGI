#!/usr/bin/env perl
use strict;
use warnings;
use Test2::V0;
use File::Temp qw(tempdir);

use lib 'lib';
use PAGI::Simple::View;

my $tmpdir = tempdir(CLEANUP => 1);

#-------------------------------------------------------------------------
# Step 1 Tests: prepend and preamble configuration options
#-------------------------------------------------------------------------
subtest 'Default behavior without prepend/preamble' => sub {
    my $view = PAGI::Simple::View->new(
        template_dir => $tmpdir,
        auto_escape  => 1,
        cache        => 0,
    );

    my $output = $view->render_string('<%= $v->name %>', name => 'World');
    is($output, 'World', 'Basic template works without custom prepend');
};

subtest 'Custom prepend option' => sub {
    my $view = PAGI::Simple::View->new(
        template_dir => $tmpdir,
        auto_escape  => 1,
        cache        => 0,
        prepend      => 'my $greeting = "Hello";',
    );

    my $output = $view->render_string(
        '<%= $greeting %>, <%= $v->name %>!',
        name => 'World'
    );
    is($output, 'Hello, World!', 'Custom prepend code is available in template');
};

subtest 'Preamble enables signatures' => sub {
    my $view = PAGI::Simple::View->new(
        template_dir => $tmpdir,
        auto_escape  => 1,
        cache        => 0,
        preamble     => 'use experimental "signatures";',
    );

    # Test that signatures work with a simple helper that accepts a coderef
    my $output = $view->render_string(
        '<% my $test = sub ($x) { return $x * 2 }; %><%= $test->(21) %>',
    );
    is($output, '42', 'Signatures work when enabled via preamble');
};

subtest 'Traditional @_ still works' => sub {
    my $view = PAGI::Simple::View->new(
        template_dir => $tmpdir,
        auto_escape  => 1,
        cache        => 0,
    );

    my $output = $view->render_string(
        '<% my $test = sub { my ($x) = @_; return $x * 2 }; %><%= $test->(21) %>',
    );
    is($output, '42', 'Traditional @_ syntax works without preamble');
};

#-------------------------------------------------------------------------
# Step 2 Tests: content_for with coderef
#-------------------------------------------------------------------------
subtest 'content_for with string (backward compatible)' => sub {
    my $view = PAGI::Simple::View->new(
        template_dir => $tmpdir,
        auto_escape  => 1,
        cache        => 0,
    );

    # Create layout
    open my $fh, '>', "$tmpdir/layout_cf.html.ep" or die $!;
    print $fh '<head><%= content("scripts") %></head><body><%= content() %></body>';
    close $fh;

    # Create page
    open my $fh2, '>', "$tmpdir/page_cf.html.ep" or die $!;
    print $fh2 '<% extends("layout_cf") %><% content_for("scripts", "<script>alert(1)</script>") %><p>Body</p>';
    close $fh2;

    my $output = $view->render('page_cf');
    like($output, qr/<head>.*<script>.*<\/head>/s, 'content_for with string works');
    like($output, qr/<body>.*<p>Body<\/p>.*<\/body>/s, 'Body content rendered');
};

subtest 'content_for with coderef' => sub {
    my $view = PAGI::Simple::View->new(
        template_dir => $tmpdir,
        auto_escape  => 1,
        cache        => 0,
    );

    # Create layout
    open my $fh, '>', "$tmpdir/layout_cfb.html.ep" or die $!;
    print $fh '<head><%= content("scripts") %></head><body><%= content() %></body>';
    close $fh;

    # Create page with block syntax
    open my $fh2, '>', "$tmpdir/page_cfb.html.ep" or die $!;
    print $fh2 q{<% extends("layout_cfb") %><% content_for("scripts", sub { %>
<script src="app.js"></script>
<script>init();</script>
<% }) %><p>Body</p>};
    close $fh2;

    my $output = $view->render('page_cfb');
    like($output, qr/<head>.*<script src="app\.js">.*<\/head>/s, 'content_for with coderef captures content');
    like($output, qr/init\(\)/, 'Multi-line content captured');
};

subtest 'content_for coderef receives $view argument' => sub {
    my $view = PAGI::Simple::View->new(
        template_dir => $tmpdir,
        auto_escape  => 1,
        cache        => 0,
        preamble     => 'use experimental "signatures";',
    );

    # Create a partial
    open my $fh, '>', "$tmpdir/_script_tag.html.ep" or die $!;
    print $fh '<script src="<%= $v->src %>"></script>';
    close $fh;

    # Create layout
    open my $fh2, '>', "$tmpdir/layout_cfv.html.ep" or die $!;
    print $fh2 '<head><%= content("scripts") %></head><body><%= content() %></body>';
    close $fh2;

    # Create page that uses $view in the block
    open my $fh3, '>', "$tmpdir/page_cfv.html.ep" or die $!;
    print $fh3 q{<% extends("layout_cfv") %><% content_for("scripts", sub ($view) { %>
<%= $view->include("_script_tag", src => "app.js") %>
<% }) %><p>Body</p>};
    close $fh3;

    my $output = $view->render('page_cfv');
    like($output, qr/<script src="app\.js">/, '$view->include works inside content_for block');
};

#-------------------------------------------------------------------------
# Step 3 Tests: block with coderef
#-------------------------------------------------------------------------
subtest 'block with string (backward compatible)' => sub {
    my $view = PAGI::Simple::View->new(
        template_dir => $tmpdir,
        auto_escape  => 1,
        cache        => 0,
    );

    # Create layout
    open my $fh, '>', "$tmpdir/layout_blk.html.ep" or die $!;
    print $fh '<nav><%= content("nav") %></nav><main><%= content() %></main>';
    close $fh;

    # Create page
    open my $fh2, '>', "$tmpdir/page_blk.html.ep" or die $!;
    print $fh2 '<% extends("layout_blk") %><% block("nav", "<a>Home</a>") %><p>Content</p>';
    close $fh2;

    my $output = $view->render('page_blk');
    like($output, qr/<nav>.*<a>Home<\/a>.*<\/nav>/s, 'block with string works');
};

subtest 'block with coderef' => sub {
    my $view = PAGI::Simple::View->new(
        template_dir => $tmpdir,
        auto_escape  => 1,
        cache        => 0,
    );

    # Create layout
    open my $fh, '>', "$tmpdir/layout_blkb.html.ep" or die $!;
    print $fh '<nav><%= content("nav") %></nav><main><%= content() %></main>';
    close $fh;

    # Create page with block syntax
    open my $fh2, '>', "$tmpdir/page_blkb.html.ep" or die $!;
    print $fh2 q{<% extends("layout_blkb") %><% block("nav", sub { %>
<a href="/">Home</a>
<a href="/about">About</a>
<% }) %><p>Content</p>};
    close $fh2;

    my $output = $view->render('page_blkb');
    like($output, qr/<nav>.*<a href="\/">Home<\/a>.*<\/nav>/s, 'block with coderef captures content');
    like($output, qr/About/, 'Multi-line block content captured');
};

#-------------------------------------------------------------------------
# Step 4 Tests: capture helper
#-------------------------------------------------------------------------
subtest 'capture helper' => sub {
    my $view = PAGI::Simple::View->new(
        template_dir => $tmpdir,
        auto_escape  => 1,
        cache        => 0,
    );

    my $output = $view->render_string(q{
<% my $card = capture(sub { %>
<div class="card"><%= $v->title %></div>
<% }); %>
First: <%= raw($card) %>
Second: <%= raw($card) %>
}, title => 'Hello');

    like($output, qr/First:.*<div class="card">Hello<\/div>/s, 'capture returns content');
    like($output, qr/Second:.*<div class="card">Hello<\/div>/s, 'captured content can be reused');
};

subtest 'capture with $view argument' => sub {
    my $view = PAGI::Simple::View->new(
        template_dir => $tmpdir,
        auto_escape  => 1,
        cache        => 0,
        preamble     => 'use experimental "signatures";',
    );

    # Create partial
    open my $fh, '>', "$tmpdir/_badge.html.ep" or die $!;
    print $fh '<span class="badge"><%= $v->text %></span>';
    close $fh;

    my $output = $view->render_string(q{
<% my $badge = capture(sub ($view) { %>
<%= $view->include("_badge", text => "New") %>
<% }); %>
<%= raw($badge) %>
}, );

    like($output, qr/<span class="badge">New<\/span>/, 'capture block can use $view->include');
};

done_testing;
