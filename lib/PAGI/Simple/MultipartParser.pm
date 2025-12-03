package PAGI::Simple::MultipartParser;

use strict;
use warnings;
use experimental 'signatures';

our $VERSION = '0.01';

use File::Temp ();
use PAGI::Simple::Upload;

=head1 NAME

PAGI::Simple::MultipartParser - Parse multipart/form-data requests

=head1 SYNOPSIS

    use PAGI::Simple::MultipartParser;

    my $parser = PAGI::Simple::MultipartParser->new(
        max_file_size    => 10 * 1024 * 1024,  # 10MB per file
        max_total_size   => 50 * 1024 * 1024,  # 50MB total
        memory_threshold => 64 * 1024,          # 64KB in memory
        temp_dir         => '/tmp',
    );

    my $result = $parser->parse($content_type, $body);
    # $result = {
    #     fields  => { name => 'value', ... },
    #     uploads => { file => [Upload, ...], ... },
    # }

=head1 DESCRIPTION

PAGI::Simple::MultipartParser handles parsing of multipart/form-data encoded
request bodies, commonly used for file uploads.

Small files are kept in memory for efficiency, while larger files are
automatically spooled to temporary files to prevent memory exhaustion.

=head1 METHODS

=cut

=head2 new

    my $parser = PAGI::Simple::MultipartParser->new(%options);

Create a new parser instance.

Options:

=over 4

=item * max_file_size - Maximum size per file in bytes (default: 10MB)

=item * max_total_size - Maximum total upload size (default: 50MB)

=item * memory_threshold - Files larger than this are spooled to disk (default: 64KB)

=item * temp_dir - Directory for temp files (default: system temp)

=back

=cut

sub new ($class, %opts) {
    my $self = bless {
        max_file_size    => $opts{max_file_size}    // (10 * 1024 * 1024),
        max_total_size   => $opts{max_total_size}   // (50 * 1024 * 1024),
        memory_threshold => $opts{memory_threshold} // (64 * 1024),
        temp_dir         => $opts{temp_dir}         // File::Temp::tempdir(CLEANUP => 1),
    }, $class;

    return $self;
}

=head2 parse

    my $result = $parser->parse($content_type, $body);

Parse a multipart/form-data body.

Returns a hashref with:

=over 4

=item * fields - Hashref of regular form fields (field_name => value or [values])

=item * uploads - Hashref of uploaded files (field_name => [Upload objects])

=back

Dies if the content type is not multipart/form-data or if limits are exceeded.

=cut

sub parse ($self, $content_type, $body) {
    # Extract boundary from content type
    my $boundary = $self->_extract_boundary($content_type);
    die "No boundary found in Content-Type" unless $boundary;

    # Check total size
    if (length($body) > $self->{max_total_size}) {
        die "Request body exceeds maximum size limit";
    }

    my %fields;
    my %uploads;

    # Split body into parts
    my @parts = $self->_split_parts($body, $boundary);

    for my $part (@parts) {
        my ($headers, $content) = $self->_parse_part($part);
        next unless $headers;

        # Parse Content-Disposition
        my $disposition = $headers->{'content-disposition'} // '';
        my ($name, $filename) = $self->_parse_disposition($disposition);

        next unless defined $name;

        if (defined $filename && length $filename) {
            # This is a file upload
            my $content_type = $headers->{'content-type'} // 'application/octet-stream';

            # Check file size
            if (length($content) > $self->{max_file_size}) {
                die "File '$filename' exceeds maximum size limit";
            }

            my $upload;
            if (length($content) > $self->{memory_threshold}) {
                # Spool to temp file
                my $tempfile = $self->_write_tempfile($content);
                $upload = PAGI::Simple::Upload->new(
                    name         => $name,
                    filename     => $filename,
                    content_type => $content_type,
                    tempfile     => $tempfile,
                    size         => length($content),
                    headers      => $headers,
                );
            }
            else {
                # Keep in memory
                $upload = PAGI::Simple::Upload->new(
                    name         => $name,
                    filename     => $filename,
                    content_type => $content_type,
                    content      => $content,
                    size         => length($content),
                    headers      => $headers,
                );
            }

            push @{$uploads{$name}}, $upload;
        }
        else {
            # This is a regular form field
            # Handle multiple values for same field
            if (exists $fields{$name}) {
                if (ref $fields{$name} eq 'ARRAY') {
                    push @{$fields{$name}}, $content;
                }
                else {
                    $fields{$name} = [$fields{$name}, $content];
                }
            }
            else {
                $fields{$name} = $content;
            }
        }
    }

    return {
        fields  => \%fields,
        uploads => \%uploads,
    };
}

# Extract boundary from Content-Type header
sub _extract_boundary ($self, $content_type) {
    return unless $content_type;

    # Match boundary parameter (handles quoted and unquoted)
    if ($content_type =~ /boundary\s*=\s*"?([^";,\s]+)"?/i) {
        return $1;
    }

    return;
}

# Split body into parts using boundary
sub _split_parts ($self, $body, $boundary) {
    my @parts;

    # The boundary marker is "--$boundary"
    my $delim = "--$boundary";
    my $end   = "--$boundary--";

    # Split on boundary
    my @chunks = split /\Q$delim\E/, $body;

    # Skip preamble (first chunk before first boundary)
    shift @chunks;

    for my $chunk (@chunks) {
        # Skip if this is the final boundary marker
        last if $chunk =~ /^--/;

        # Remove leading CRLF and trailing CRLF
        $chunk =~ s/^\r?\n//;
        $chunk =~ s/\r?\n$//;

        push @parts, $chunk if length $chunk;
    }

    return @parts;
}

# Parse a single part into headers and content
sub _parse_part ($self, $part) {
    # Headers and body are separated by blank line
    my ($header_section, $content) = split /\r?\n\r?\n/, $part, 2;

    return (undef, undef) unless defined $header_section;

    # Parse headers
    my %headers;
    for my $line (split /\r?\n/, $header_section) {
        if ($line =~ /^([^:]+):\s*(.*)$/) {
            $headers{lc $1} = $2;
        }
    }

    return (\%headers, $content // '');
}

# Parse Content-Disposition header
sub _parse_disposition ($self, $disposition) {
    return (undef, undef) unless $disposition;

    my ($name, $filename);

    # Extract name parameter
    if ($disposition =~ /\bname\s*=\s*"([^"]*)"/ ||
        $disposition =~ /\bname\s*=\s*([^;\s]+)/) {
        $name = $1;
    }

    # Extract filename parameter
    if ($disposition =~ /\bfilename\s*=\s*"([^"]*)"/ ||
        $disposition =~ /\bfilename\s*=\s*([^;\s]+)/) {
        $filename = $1;
    }

    # Handle filename* (RFC 5987) - encoded filename
    if ($disposition =~ /\bfilename\*\s*=\s*([^;\s]+)/) {
        my $encoded = $1;
        # Format: charset'language'encoded_value
        if ($encoded =~ /^(?:utf-8|iso-8859-1)''(.+)$/i) {
            $filename = _percent_decode($1);
        }
    }

    return ($name, $filename);
}

# Write content to temp file
sub _write_tempfile ($self, $content) {
    my ($fh, $filename) = File::Temp::tempfile(
        DIR    => $self->{temp_dir},
        UNLINK => 0,  # Don't auto-delete, Upload object handles cleanup
    );

    binmode $fh, ':raw';
    print $fh $content;
    close $fh;

    return $filename;
}

# Percent-decode a string (for RFC 5987 filenames)
sub _percent_decode ($str) {
    return '' unless defined $str;
    $str =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/ge;
    return $str;
}

=head1 SEE ALSO

L<PAGI::Simple::Upload>, L<PAGI::Simple::Request>

=head1 AUTHOR

PAGI Contributors

=cut

1;
