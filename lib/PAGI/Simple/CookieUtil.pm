package PAGI::Simple::CookieUtil;

use strict;
use warnings;
use experimental 'signatures';

our $VERSION = '0.01';

use Cookie::Baker ();

=head1 NAME

PAGI::Simple::CookieUtil - Cookie utilities for PAGI::Simple using Cookie::Baker

=head1 SYNOPSIS

    use PAGI::Simple::CookieUtil;

    # Parse cookies from request header
    my $cookies = PAGI::Simple::CookieUtil::parse_cookie_header($header);
    # $cookies = { foo => 'bar', session => 'abc123' }

    # Format a Set-Cookie header
    my $header = PAGI::Simple::CookieUtil::format_set_cookie('session', 'abc123',
        expires  => time() + 3600,  # 1 hour from now
        path     => '/',
        secure   => 1,
        httponly => 1,
        samesite => 'Strict',
    );

=head1 DESCRIPTION

PAGI::Simple::CookieUtil provides cookie parsing and formatting utilities
for PAGI::Simple. It uses L<Cookie::Baker> internally for RFC 6265 compliant
cookie handling.

=head1 FUNCTIONS

=head2 parse_cookie_header

    my $cookies = PAGI::Simple::CookieUtil::parse_cookie_header($header);

Parse a Cookie header string into a hashref of name => value pairs.

Returns an empty hashref if the header is empty or undefined.

=cut

sub parse_cookie_header ($header) {
    return {} unless defined $header && length $header;
    return Cookie::Baker::crush_cookie($header);
}

=head2 format_set_cookie

    my $header = PAGI::Simple::CookieUtil::format_set_cookie($name, $value, %opts);

Format a Set-Cookie header string.

Options:

=over 4

=item * expires - Expiration time as epoch timestamp

=item * max_age - Max-Age in seconds (alternative to expires)

=item * domain - Cookie domain

=item * path - Cookie path (default: '/')

=item * secure - Boolean, set Secure flag

=item * httponly - Boolean, set HttpOnly flag

=item * samesite - SameSite attribute: 'Strict', 'Lax', or 'None'

=back

=cut

sub format_set_cookie ($name, $value, %opts) {
    my %cookie_opts = (
        value => $value,
        path  => $opts{path} // '/',
    );

    # Map our option names to Cookie::Baker's expected keys
    $cookie_opts{domain}   = $opts{domain}   if defined $opts{domain};
    $cookie_opts{expires}  = $opts{expires}  if defined $opts{expires};
    $cookie_opts{'max-age'} = $opts{max_age} if defined $opts{max_age};
    $cookie_opts{secure}   = $opts{secure}   if $opts{secure};
    $cookie_opts{httponly} = $opts{httponly} if $opts{httponly};
    $cookie_opts{samesite} = $opts{samesite} if defined $opts{samesite};

    return Cookie::Baker::bake_cookie($name, \%cookie_opts);
}

=head2 format_removal_cookie

    my $header = PAGI::Simple::CookieUtil::format_removal_cookie($name, %opts);

Format a Set-Cookie header that removes/expires a cookie.

Sets the cookie value to empty and expiration to epoch 0.

Options: path, domain (to match the original cookie scope).

=cut

sub format_removal_cookie ($name, %opts) {
    my %cookie_opts = (
        value   => '',
        expires => 0,  # Epoch 0 = expired
        path    => $opts{path} // '/',
    );

    $cookie_opts{domain} = $opts{domain} if defined $opts{domain};

    return Cookie::Baker::bake_cookie($name, \%cookie_opts);
}

=head1 MIGRATION FROM PAGI::Simple::Cookie

This module replaces the previous C<PAGI::Simple::Cookie> module.

=head2 Breaking Changes

=over 4

=item * Relative time syntax removed

The old module supported relative time strings like C<+1h>, C<+30d>, C<+1y>.
These are no longer supported. Use epoch timestamps instead:

    # Old (no longer supported)
    expires => '+1h'

    # New
    expires => time() + 3600

=item * OO interface removed

The old module had a C<new()> constructor and instance methods.
Use the functional interface instead.

=back

=head1 SEE ALSO

L<Cookie::Baker>, L<PAGI::Simple::Request>, L<PAGI::Simple::Context>

=head1 AUTHOR

PAGI Contributors

=cut

1;
