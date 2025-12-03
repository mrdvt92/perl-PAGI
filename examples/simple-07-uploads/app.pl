#!/usr/bin/env perl

# File Upload Example
#
# This example demonstrates file upload handling with PAGI::Simple:
# - Single file upload
# - Multiple file uploads
# - File validation (type, size)
# - Saving uploaded files
#
# Run with:
#   pagi-server --port 3000 app.pl
#
# Test with:
#   curl -F "avatar=@photo.jpg" http://localhost:3000/upload
#   curl -F "files=@a.txt" -F "files=@b.txt" http://localhost:3000/multi

use strict;
use warnings;
use experimental 'signatures';

use PAGI::Simple;
use Future::AsyncAwait;
use File::Temp qw(tempdir);
use File::Spec;
use JSON::PP;

my $app = PAGI::Simple->new;

# Create upload directory
my $upload_dir = tempdir(CLEANUP => 1);

# --- Demo page ---

$app->get('/' => sub ($c) {
    my $html = <<'HTML';
<!DOCTYPE html>
<html>
<head>
    <title>File Upload Demo</title>
    <style>
        body { font-family: sans-serif; max-width: 800px; margin: 50px auto; padding: 0 20px; }
        h1 { color: #333; }
        .section { margin: 20px 0; padding: 20px; background: #f5f5f5; border-radius: 5px; }
        form { margin: 10px 0; }
        input[type="file"] { margin: 10px 0; display: block; }
        input[type="submit"] { padding: 10px 20px; background: #007bff; color: white; border: none; border-radius: 5px; cursor: pointer; }
        input[type="submit"]:hover { background: #0056b3; }
        pre { background: #222; color: #0f0; padding: 15px; border-radius: 5px; overflow-x: auto; }
        .result { margin-top: 15px; padding: 10px; border: 1px solid #ccc; border-radius: 5px; }
        .error { background: #fee; border-color: #f00; }
        .success { background: #efe; border-color: #0f0; }
    </style>
</head>
<body>
    <h1>File Upload Demo</h1>

    <div class="section">
        <h2>Single File Upload</h2>
        <form action="/upload" method="POST" enctype="multipart/form-data">
            <label>Avatar Image:</label>
            <input type="file" name="avatar" accept="image/*">
            <input type="submit" value="Upload">
        </form>
    </div>

    <div class="section">
        <h2>Multiple File Upload</h2>
        <form action="/multi" method="POST" enctype="multipart/form-data">
            <label>Select multiple files:</label>
            <input type="file" name="files" multiple>
            <input type="submit" value="Upload All">
        </form>
    </div>

    <div class="section">
        <h2>Upload with Metadata</h2>
        <form action="/upload-with-info" method="POST" enctype="multipart/form-data">
            <label>Title:</label>
            <input type="text" name="title" placeholder="Document title">
            <label>Description:</label>
            <input type="text" name="description" placeholder="Description">
            <label>File:</label>
            <input type="file" name="document">
            <input type="submit" value="Upload Document">
        </form>
    </div>

    <div class="section">
        <h2>Test with curl</h2>
        <pre># Single file upload
curl -F "avatar=@photo.jpg" http://localhost:3000/upload

# Multiple files
curl -F "files=@a.txt" -F "files=@b.txt" http://localhost:3000/multi

# With metadata
curl -F "title=My Doc" -F "description=Test" -F "document=@file.pdf" \
  http://localhost:3000/upload-with-info

# Check uploads
curl http://localhost:3000/list</pre>
    </div>
</body>
</html>
HTML
    $c->html($html);
});

# --- Single file upload ---

$app->post('/upload' => sub ($c) {
    my $file = $c->req->upload('avatar')->get;

    unless ($file) {
        return $c->status(400)->json({
            error => 'No file uploaded',
            field => 'avatar',
        });
    }

    if ($file->is_empty) {
        return $c->status(400)->json({
            error => 'Empty file',
        });
    }

    # Validate file type (example: images only)
    my $type = $file->content_type;
    unless ($type =~ m{^image/}) {
        return $c->status(400)->json({
            error   => 'Invalid file type',
            got     => $type,
            allowed => 'image/*',
        });
    }

    # Validate file size (max 5MB)
    my $max_size = 5 * 1024 * 1024;
    if ($file->size > $max_size) {
        return $c->status(400)->json({
            error    => 'File too large',
            size     => $file->size,
            max_size => $max_size,
        });
    }

    # Generate safe filename
    my $safe_name = time() . '_' . _sanitize_filename($file->basename);
    my $dest = File::Spec->catfile($upload_dir, $safe_name);

    # Save file
    $file->move_to($dest);

    $c->json({
        success  => 1,
        message  => 'File uploaded successfully',
        filename => $file->filename,
        saved_as => $safe_name,
        size     => $file->size,
        type     => $file->content_type,
    });
});

# --- Multiple file upload ---

$app->post('/multi' => sub ($c) {
    my $files = $c->req->uploads('files')->get;

    unless (@$files) {
        return $c->status(400)->json({
            error => 'No files uploaded',
        });
    }

    my @results;
    my @errors;

    for my $file (@$files) {
        if ($file->is_empty) {
            push @errors, {
                filename => $file->filename,
                error    => 'Empty file',
            };
            next;
        }

        # Generate safe filename
        my $safe_name = time() . '_' . int(rand(10000)) . '_' . _sanitize_filename($file->basename);
        my $dest = File::Spec->catfile($upload_dir, $safe_name);

        eval {
            $file->move_to($dest);
            push @results, {
                filename => $file->filename,
                saved_as => $safe_name,
                size     => $file->size,
                type     => $file->content_type,
            };
        };
        if ($@) {
            push @errors, {
                filename => $file->filename,
                error    => "$@",
            };
        }
    }

    $c->json({
        success => 1,
        total   => scalar(@$files),
        saved   => scalar(@results),
        failed  => scalar(@errors),
        files   => \@results,
        errors  => \@errors,
    });
});

# --- Upload with metadata ---

$app->post('/upload-with-info' => sub ($c) {
    # Get form fields
    my $body = $c->req->body->get;

    # For multipart, fields are also parsed
    my $parser = PAGI::Simple::MultipartParser->new;
    my $ct = $c->req->content_type;
    my $result = eval { $parser->parse($ct, $body) } // { fields => {}, uploads => {} };

    my $title = $result->{fields}{title} // 'Untitled';
    my $description = $result->{fields}{description} // '';
    my $file = ($result->{uploads}{document} // [])->[0];

    unless ($file) {
        return $c->status(400)->json({
            error => 'No document uploaded',
        });
    }

    # Generate safe filename
    my $safe_name = time() . '_' . _sanitize_filename($file->basename);
    my $dest = File::Spec->catfile($upload_dir, $safe_name);

    $file->move_to($dest);

    $c->json({
        success     => 1,
        title       => $title,
        description => $description,
        file        => {
            filename => $file->filename,
            saved_as => $safe_name,
            size     => $file->size,
            type     => $file->content_type,
        },
    });
});

# --- List uploaded files ---

$app->get('/list' => sub ($c) {
    opendir my $dh, $upload_dir or die "Cannot open upload dir: $!";
    my @files = grep { -f File::Spec->catfile($upload_dir, $_) } readdir($dh);
    closedir $dh;

    my @info;
    for my $file (@files) {
        my $path = File::Spec->catfile($upload_dir, $file);
        push @info, {
            name => $file,
            size => -s $path,
        };
    }

    $c->json({
        upload_dir => $upload_dir,
        file_count => scalar(@info),
        files      => \@info,
    });
});

# --- Check if request is multipart ---

$app->post('/check' => sub ($c) {
    $c->json({
        is_multipart => $c->req->is_multipart ? 1 : 0,
        content_type => $c->req->content_type,
        has_uploads  => $c->req->has_uploads->get ? 1 : 0,
    });
});

# --- Helper: Sanitize filename ---

sub _sanitize_filename ($filename) {
    # Remove path components
    $filename =~ s{.*[/\\]}{}g;

    # Replace dangerous characters
    $filename =~ s/[^a-zA-Z0-9._-]/_/g;

    # Prevent empty filename
    $filename = 'unnamed' unless length $filename;

    # Limit length
    $filename = substr($filename, 0, 100) if length($filename) > 100;

    return $filename;
}

$app->to_app;
