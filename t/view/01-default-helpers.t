#!/usr/bin/env perl
use strict;
use warnings;
use Test2::V0;
use File::Temp qw(tempdir);

use lib 'lib';
use PAGI::Simple::View;

# Create temp directory for templates
my $tmpdir = tempdir(CLEANUP => 1);

# Create a simple view instance for testing
my $view = PAGI::Simple::View->new(
    template_dir => $tmpdir,
    auto_escape  => 1,
    cache        => 0,
);

#-------------------------------------------------------------------------
# Test: raw() helper - outputs without escaping
#-------------------------------------------------------------------------
subtest 'raw() helper bypasses auto-escaping' => sub {
    my $output = $view->render_string(
        '<%= raw("<b>bold</b>") %>',
    );
    like($output, qr/<b>bold<\/b>/, 'raw() outputs unescaped HTML');

    # Compare with auto-escaped version
    my $escaped = $view->render_string(
        '<%= "<b>bold</b>" %>',
    );
    like($escaped, qr/&lt;b&gt;/, 'Normal output is escaped');
};

#-------------------------------------------------------------------------
# Test: safe() helper - escapes and marks as safe
#-------------------------------------------------------------------------
subtest 'safe() helper escapes and marks as safe' => sub {
    my $output = $view->render_string(
        '<%= safe("<script>alert(1)</script>") %>',
    );
    like($output, qr/&lt;script&gt;/, 'safe() escapes HTML');
    unlike($output, qr/<script>/, 'No raw script tag present');
};

#-------------------------------------------------------------------------
# Test: safe_concat() helper - concatenates safe strings
#-------------------------------------------------------------------------
subtest 'safe_concat() helper concatenates multiple strings' => sub {
    my $output = $view->render_string(
        '<%= safe_concat("<a>", "<b>", "<c>") %>',
    );
    like($output, qr/&lt;a&gt;&lt;b&gt;&lt;c&gt;/, 'safe_concat() escapes and joins');
};

#-------------------------------------------------------------------------
# Test: html_escape() helper - escapes HTML entities
# NOTE: html_escape is defined in default_helpers but the method is missing
# in Template::EmbeddedPerl - this is an upstream bug. Using safe() instead
# which does the same thing.
#-------------------------------------------------------------------------
subtest 'safe() can be used for HTML escaping' => sub {
    my $output = $view->render_string(
        '<%= safe("<div>&amp;</div>") %>',
    );
    like($output, qr/&lt;div&gt;/, 'safe() escapes < and >');
    like($output, qr/&amp;amp;/, 'safe() escapes &');
};

#-------------------------------------------------------------------------
# Test: url_encode() helper - encodes URL parameters
#-------------------------------------------------------------------------
subtest 'url_encode() helper encodes URL parameters' => sub {
    my $output = $view->render_string(
        '<%= url_encode("hello world&foo=bar") %>',
    );
    like($output, qr/hello%20world/, 'url_encode() encodes spaces');
    like($output, qr/%26/, 'url_encode() encodes &');
    like($output, qr/%3D/, 'url_encode() encodes =');
};

#-------------------------------------------------------------------------
# Test: escape_javascript() helper - escapes JS strings
# Note: When used with auto_escape=1, the backslash-escaped output
# is then HTML escaped, so \' becomes \&#39; which is correct for
# embedding JavaScript in HTML.
#-------------------------------------------------------------------------
subtest 'escape_javascript() helper escapes JavaScript' => sub {
    # Test with raw() to see the pure JS escaping
    my $output = $view->render_string(
        q{<%= raw(escape_javascript("alert('hello')")) %>},
    );
    like($output, qr/alert\(\\'hello\\'\)/, 'escape_javascript() escapes single quotes');

    my $output2 = $view->render_string(
        q{<%= raw(escape_javascript("line1\nline2")) %>},
    );
    like($output2, qr/line1\\nline2/, 'escape_javascript() escapes newlines');
};

#-------------------------------------------------------------------------
# Test: trim() helper - trims whitespace
#-------------------------------------------------------------------------
subtest 'trim() helper removes leading/trailing whitespace' => sub {
    my $output = $view->render_string(
        '<%= trim("  hello world  ") %>',
    );
    is($output, 'hello world', 'trim() removes surrounding whitespace');
};

#-------------------------------------------------------------------------
# Test: mtrim() helper - trims whitespace from multiline
#-------------------------------------------------------------------------
subtest 'mtrim() helper trims multiline whitespace' => sub {
    my $output = $view->render_string(
        '<%= mtrim("  line1  \n  line2  ") %>',
    );
    like($output, qr/^line1\s*\nline2$/, 'mtrim() trims each line');
};

#-------------------------------------------------------------------------
# Test: All default helpers available in templates
# NOTE: html_escape is skipped as it's broken in upstream Template::EmbeddedPerl
#-------------------------------------------------------------------------
subtest 'All default helpers are available' => sub {
    # Test that calling each helper doesn't die
    # Skipping html_escape as it's broken in Template::EmbeddedPerl
    my @helpers = qw(raw safe safe_concat url_encode escape_javascript trim mtrim);

    for my $helper (@helpers) {
        my $output = eval {
            $view->render_string(qq{<%= $helper("test") %>});
        };
        ok(!$@, "$helper() is available") or diag $@;
    }
};

#-------------------------------------------------------------------------
# Test: Custom helpers still work alongside defaults
#-------------------------------------------------------------------------
subtest 'Custom helpers work alongside defaults' => sub {
    # Create a template file to test include() still works
    open my $fh, '>', "$tmpdir/partial.html.ep" or die $!;
    print $fh 'Hello, <%= $v->{name} %>!';
    close $fh;

    my $output = $view->render_string(
        '<%= include("partial", name => "World") %>',
    );
    like($output, qr/Hello, World!/, 'include() helper still works');
};

#-------------------------------------------------------------------------
# Test: Layout helpers still work alongside defaults
#-------------------------------------------------------------------------
subtest 'Layout helpers work alongside defaults' => sub {
    # Create layout
    open my $fh1, '>', "$tmpdir/layout.html.ep" or die $!;
    print $fh1 '<html><%= content() %></html>';
    close $fh1;

    # Create page
    open my $fh2, '>', "$tmpdir/page.html.ep" or die $!;
    print $fh2 '<% extends("layout") %><body>Content</body>';
    close $fh2;

    my $output = $view->render('page');
    like($output, qr/<html><body>Content<\/body><\/html>/, 'extends/content helpers still work');
};

done_testing;
