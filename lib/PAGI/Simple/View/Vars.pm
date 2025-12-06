package PAGI::Simple::View::Vars;

use strict;
use warnings;
use experimental 'signatures';

our $VERSION = '0.01';

use Carp qw(croak);

=head1 NAME

PAGI::Simple::View::Vars - Template variable accessor with method syntax

=head1 SYNOPSIS

    # In templates, variables are accessed via $v:
    <%= $v->title %>
    <%= $v->user->name %>

    # For performance-sensitive loops, hash access is also available:
    <% for my $item (@{$v->{items}}) { %>
        <%= $item->{name} %>
    <% } %>

=head1 DESCRIPTION

PAGI::Simple::View::Vars provides method-style access to template variables.
Instead of C<< $v->{title} >>, you can write C<< $v->title >>.

Key features:

=over 4

=item * B<Clean syntax> - C<< $v->title >> instead of C<< $v->{title} >>

=item * B<Error detection> - Throws an error if you access a variable that
wasn't passed to the template, catching typos early

=item * B<Performance> - Uses AUTOLOAD with method caching, so repeated access
is as fast as a regular method call

=item * B<Hash fallback> - You can still use C<< $v->{key} >> for dynamic keys
or in tight loops where you want to avoid any method call overhead

=back

=head1 METHODS

=head2 new

    my $vars = PAGI::Simple::View::Vars->new(\%hash);

Create a new Vars object wrapping the given hashref.

=cut

sub new ($class, $hash) {
    croak "Vars requires a hashref" unless ref $hash eq 'HASH';
    return bless $hash, $class;
}

=head2 has

    if ($v->has('title')) { ... }

Check if a variable exists (was passed to the template).
Returns true if the key exists, even if the value is undef.

=cut

sub has ($self, $key) {
    return exists $self->{$key};
}

=head2 keys

    my @keys = $v->keys;

Returns a list of all variable names.

=cut

sub keys ($self) {
    return keys %$self;
}

=head2 Hash access

    my $value = $v->{key};
    my $value = $v->{$dynamic_key};

Direct hash access is always available. Use this for:

=over 4

=item * Dynamic keys that aren't known at write time

=item * Performance-critical tight loops

=item * When you want to allow missing keys (returns undef instead of error)

=back

=cut

# AUTOLOAD provides method-style access with caching
# First call to $v->foo hits AUTOLOAD, installs foo() method, returns value
# Subsequent calls to $v->foo go directly to the installed method (fast!)
sub AUTOLOAD ($self) {
    my $method = our $AUTOLOAD;
    $method =~ s/.*:://;

    # Don't handle DESTROY or all-caps methods
    return if $method eq 'DESTROY';
    return if $method =~ /^[A-Z_]+$/;

    # Check if the key exists - error on typos
    unless (exists $self->{$method}) {
        my @caller = caller(0);
        croak "Unknown template variable '$method'. "
            . "Available variables: " . join(', ', sort CORE::keys %$self);
    }

    # Install the method for future calls (caching)
    my $key = $method;  # Capture for closure
    no strict 'refs';
    *{$AUTOLOAD} = sub ($self) {
        unless (exists $self->{$key}) {
            croak "Unknown template variable '$key'. "
                . "Available variables: " . join(', ', sort CORE::keys %$self);
        }
        return $self->{$key};
    };

    # Return the value for this call
    return $self->{$method};
}

# Prevent AUTOLOAD from being called for DESTROY
sub DESTROY { }

# Override can() to report that we can handle any key
sub can ($self, $method) {
    # For class method calls, use default behavior
    return $self->SUPER::can($method) unless ref $self;

    # For instance calls, we "can" do any key that exists
    return sub { $self->{$method} } if exists $self->{$method};

    # Fall back to default for real methods
    return $self->SUPER::can($method);
}

=head1 PERFORMANCE NOTES

The AUTOLOAD mechanism installs real methods after first use, so:

    # First call - hits AUTOLOAD, installs method
    $v->title;

    # All subsequent calls - direct method call, very fast
    $v->title;
    $v->title;

For the absolute lowest overhead in tight loops, use hash access:

    # Slightly faster in very hot loops
    for my $item (@{$v->{items}}) {
        print $item->{name};  # Direct hash access, no method call
    }

In practice, the difference is negligible for most templates.

=head1 SEE ALSO

L<PAGI::Simple::View>

=cut

1;
