package PAGI::Simple::View::Role::Valiant;

use strict;
use warnings;
use experimental 'signatures';

use Role::Tiny;
use Valiant::HTML::Util::Form;
use Template::EmbeddedPerl::SafeString;

our $VERSION = '0.01';

=head1 NAME

PAGI::Simple::View::Role::Valiant - Valiant form builder integration for PAGI::Simple

=head1 SYNOPSIS

    # In your app setup:
    $app->views('./templates', {
        roles => ['PAGI::Simple::View::Role::Valiant'],
    });

    # In templates:
    <%= form_for($v->user, { action => '/users' }, sub ($fb) { %>
        <div class="field">
            <%= $fb->label('name') %>
            <%= $fb->input('name') %>
            <%= $fb->errors_for('name') %>
        </div>
        <%= $fb->submit('Save') %>
    <% }) %>

=head1 DESCRIPTION

This role adds Valiant form builder support to PAGI::Simple::View.
It provides the C<form_for> helper and exposes the FormBuilder (C<$fb>)
object within form blocks for building form fields.

=head2 Requirements

Models used with C<form_for> should use L<Valiant::Validations> for
validation and error handling.

=head1 TEMPLATE HELPERS

=head2 form_for

    <%= form_for($model, \%options, sub ($fb) { ... }) %>

Create an HTML form bound to a model. The form builder C<$fb> provides
methods for generating form fields.

Options:

=over 4

=item action - Form action URL (required for PAGI::Simple)

=item method - HTTP method (default: 'post')

=item html - Additional HTML attributes for the form tag

=back

Example:

    <%= form_for($v->user, { action => '/users', method => 'post' }, sub ($fb) { %>
        <%= $fb->label('email') %>
        <%= $fb->input('email', { type => 'email', class => 'form-control' }) %>
        <%= $fb->errors_for('email', { class => 'text-danger' }) %>
        <%= $fb->submit('Save', { class => 'btn btn-primary' }) %>
    <% }) %>

=head2 FormBuilder Methods

Inside the form_for block, C<$fb> provides these methods:

=head3 Field Methods

=over 4

=item $fb->input($name, \%opts) - Text input

=item $fb->password($name, \%opts) - Password input

=item $fb->text_area($name, \%opts) - Textarea

=item $fb->checkbox($name, \%opts) - Checkbox

=item $fb->radio_button($name, $value, \%opts) - Radio button

=item $fb->select($name, \@options, \%opts) - Select dropdown

=item $fb->hidden($name, \%opts) - Hidden input

=item $fb->date_field($name, \%opts) - Date input

=item $fb->datetime_local_field($name, \%opts) - Datetime-local input

=item $fb->time_field($name, \%opts) - Time input

=back

=head3 Label and Error Methods

=over 4

=item $fb->label($name, $text, \%opts) - Label for field

=item $fb->errors_for($name, \%opts) - Error messages for field

=item $fb->model_errors(\%opts) - Model-level errors

=back

=head3 Button Methods

=over 4

=item $fb->submit($text, \%opts) - Submit button

=item $fb->button($name, \%opts, $text) - Generic button

=back

=head3 Nested Forms

=over 4

=item $fb->fields_for($name, sub ($nested_fb) { ... }) - Nested model fields

=back

=head2 htmx Integration

Add htmx attributes directly to form elements:

    <%= form_for($v->user, {
        action => '/users',
        html => {
            'hx-post' => '/users',
            'hx-target' => '#result',
            'hx-swap' => 'outerHTML'
        }
    }, sub ($fb) { %>
        <%= $fb->input('name', {
            'hx-post' => '/validate/name',
            'hx-trigger' => 'blur changed delay:500ms',
            'hx-target' => 'next .error'
        }) %>
        <span class="error"></span>
        <%= $fb->submit('Save') %>
    <% }) %>

=cut

# Accessor for the Form utility object (cached per render context)
sub _valiant_form ($self, $ctx) {
    $ctx->{_valiant_form} //= Valiant::HTML::Util::Form->new(view => $ctx);
}

=head1 HELPER METHODS

These methods are automatically available as template helpers.

=cut

# Helper: form_for
# Note: helper_ prefix methods receive ($self, $render_ctx, @args)
sub helper_form_for ($self, $ctx, $model, @args) {
    my $form = $self->_valiant_form($ctx);
    my $result = $form->form_for($model, @args);
    # Return as raw HTML (already safe)
    return Template::EmbeddedPerl::SafeString::raw($result);
}

1;

=head1 SEE ALSO

L<PAGI::Simple::View>, L<Valiant::HTML::FormBuilder>, L<Valiant::Validations>

=head1 AUTHOR

PAGI Contributors

=cut
