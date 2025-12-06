package PAGI::Simple::View::Helpers;

use strict;
use warnings;
use experimental 'signatures';

our $VERSION = '0.01';

use Exporter 'import';
use Scalar::Util qw(blessed);

our @EXPORT_OK = qw(escape raw safe is_safe);

=head1 NAME

PAGI::Simple::View::Helpers - Core template helpers for PAGI::Simple views

=head1 SYNOPSIS

    use PAGI::Simple::View::Helpers qw(escape raw safe);

    # Escape HTML entities
    my $escaped = escape('<script>alert("XSS")</script>');
    # &lt;script&gt;alert(&quot;XSS&quot;)&lt;/script&gt;

    # Mark string as raw (will not be escaped)
    my $html = raw('<b>Bold</b>');

    # Mark string as safe (already escaped)
    my $safe_str = safe($already_escaped);

=head1 DESCRIPTION

This module provides core helper functions for template rendering, including
HTML escaping and safe string handling.

=head1 FUNCTIONS

=cut

# Safe string class - prevents double-escaping
{
    package PAGI::Simple::View::SafeString;
    use overload
        '""'   => sub { ${$_[0]} },
        'bool' => sub { length(${$_[0]}) > 0 },
        fallback => 1;

    sub new ($class, $string) {
        my $s = defined $string ? "$string" : '';
        return bless \$s, $class;
    }

    sub TO_HTML ($self, $view = undef) {
        return $$self;  # Already safe, return as-is
    }
}

=head2 escape

    my $escaped = escape($string);

Escape HTML entities in a string. Returns a SafeString object that
won't be escaped again.

The following characters are escaped:
  & -> &amp;
  < -> &lt;
  > -> &gt;
  " -> &quot;
  ' -> &#39;

If the input is an object with a TO_HTML method, that method is called
and its result is treated as safe HTML.

=cut

sub escape ($text) {
    return PAGI::Simple::View::SafeString->new('') unless defined $text;

    # If already a SafeString, return as-is
    if (blessed($text) && $text->isa('PAGI::Simple::View::SafeString')) {
        return $text;
    }

    # Check for TO_HTML protocol - objects that render themselves
    if (blessed($text) && $text->can('TO_HTML')) {
        # TO_HTML should return safe HTML, so wrap the result
        my $html = $text->TO_HTML();
        return safe($html);
    }

    # Convert to string
    my $str = "$text";

    # Escape HTML entities
    $str =~ s/&/&amp;/g;
    $str =~ s/</&lt;/g;
    $str =~ s/>/&gt;/g;
    $str =~ s/"/&quot;/g;
    $str =~ s/'/&#39;/g;

    return PAGI::Simple::View::SafeString->new($str);
}

=head2 raw

    my $html = raw($html_string);

Returns a string as a safe string object B<without escaping>. Use this
for trusted HTML content that you want to output without modification.

    <%= raw '<a href="http://example.com">Example</a>' %>

B<Warning:> Never use this with user-provided input without sanitization.
This bypasses all escaping and outputs the string exactly as provided.

=cut

sub raw ($html) {
    return PAGI::Simple::View::SafeString->new(defined $html ? "$html" : '');
}

=head2 safe

    my $safe = safe($string);

Returns a string as a safe HTML B<escaped> string object that will not
be escaped again. This escapes the string first (converting < to &lt;, etc.)
and then marks the result as safe so it won't be double-escaped.

    <%= safe '<script>alert(1)</script>' %>
    # Outputs: &lt;script&gt;alert(1)&lt;/script&gt;

This is different from C<raw()> which does NOT escape the input.

=cut

sub safe ($string) {
    return escape($string);
}

=head2 is_safe

    if (is_safe($value)) { ... }

Check if a value is a SafeString (won't be escaped).

=cut

sub is_safe ($value) {
    return blessed($value) && $value->isa('PAGI::Simple::View::SafeString');
}

=head1 TO_HTML PROTOCOL

Objects can implement a TO_HTML method to define their own HTML rendering:

    package MyApp::Entity::Todo;

    sub TO_HTML ($self, $view) {
        return $view->include('todos/_item', todo => $self);
    }

When such an object is output in a template with C<< <%= $object %> >>,
the TO_HTML method is called automatically and the result is treated as
safe HTML.

=head1 SEE ALSO

L<PAGI::Simple::View>

=head1 AUTHOR

PAGI Contributors

=cut

1;
