# -*- perl -*-
# Lintian::Path -- Representation of path entry in a package

# Copyright (C) 2011 Niels Thykier
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation; either version 2 of the License, or (at your option)
# any later version.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
# FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
# more details.
#
# You should have received a copy of the GNU General Public License along with
# this program.  If not, see <http://www.gnu.org/licenses/>.

package Lintian::Path;

use strict;
use warnings;
use parent qw(Class::Accessor::Fast);
use overload (
    '""' => \&_as_string,
    'qr' => \&_as_regex_ref,
    'bool' => \&_bool,
    '!' => \&_bool_not,
    '.'  => \&_str_concat,
    'cmp' => \&_str_cmp,
    'eq' => \&_str_eq,
    'ne' => \&_str_ne,
    'fallback' => 0,
);

use Carp qw(croak confess);
use Scalar::Util qw(weaken);

use Lintian::Util qw(normalize_pkg_path slurp_entire_file);

=head1 NAME

Lintian::Path - Lintian representation of a path entry in a package

=head1 SYNOPSIS

    my ($name, $type, $dir) = ('lintian', 'source', '/path/to/entry');
    my $info = Lintian::Collect->new ($name, $type, $dir);
    my $path = $info->index('bin/ls');
    if ($path->is_file) {
       # is file (or hardlink)
       if ($path->is_hardlink) { }
       if ($path->is_regular_file) { }
    } elsif ($path->is_dir) {
       # is dir
       if ($path->owner eq 'root') { }
       if ($path->group eq 'root') { }
    } elsif ($path->is_symlink) {
       my $normalized = $path->link_normalized;
       if (defined($normalized)) {
           my $more_info = $info->index($normalized);
           if (defined($more_info)) {
               # target exists in the package...
           }
       }
    }

=head1 INSTANCE METHODS

=over 4

=item Lintian::Path->new ($data)

Internal constructor (used by Lintian::Collect::Package).

Argument is a hash containing the data read from the index file.

=cut

sub new {
    my ($type, $data) = @_;
    my $self = $data;
    my $ftype = $data->{'type'};
    bless($self, $type);
    # Use $data->{type} directly here.  The constructor is called
    # often enough for this to take up a (small) measure amount of
    # runtime.
    if ($ftype eq '-' or $ftype eq 'h') {
        $self->{'_is_open_ok'} = 1;
        $self->{'_valid_path'} = 1;
    } elsif ($ftype eq 'd') {
        $self->{'_is_open_ok'} = 0;
        $self->{'_valid_path'} = 1;
        for my $child ($self->children) {
            $child->_set_parent_dir($self);
        }
    }
    return $self;
}

=item name

Returns the name of the file (relative to the package root).

NB: It will never have any leading "./" (or "/") in it.

=item owner

Returns the owner of the path entry as a username.

NB: If only numerical owner information is available in the package,
this may return a numerical owner (except uid 0 is always mapped to
"root")

=item group

Returns the group of the path entry as a username.

NB: If only numerical owner information is available in the package,
this may return a numerical group (except gid 0 is always mapped to
"root")

=item uid

Returns the uid of the owner of the path entry.

NB: If the uid is not available, undef will be returned.
This usually happens if the numerical data is not collected (e.g. in
source packages)

=item gid

Returns the gid of the owner of the path entry.

NB: If the gid is not available, undef will be returned.
This usually happens if the numerical data is not collected (e.g. in
source packages)

=item link

If this is a link (i.e. is_symlink or is_hardlink returns a truth
value), this method returns the target of the link.

If this is not a link, then this returns undef.

If the path is a symlink this method can be used to determine if the
symlink is relative or absolute.  This is I<not> true for hardlinks,
where the link target is always relative to the root.

NB: Even for symlinks, a leading "./" will be stripped.

=item size

Returns the size of the path in bytes.

NB: This is only well defined for files.

=item date

Return the modification date as YYYY-MM-DD.

=item operm

Returns the file permissions of this object in octal (e.g. 0644).

NB: This is only well defined for file entries that are subject to
permissions (e.g. files).  Particularly, the value is not well defined
for symlinks.

=item parent_dir

Returns the parent directory entry of this entry as a
L<Lintian::Path>.

NB: Returns C<undef> for the "root" dir.

=item dirname

Returns the "directory" part of the name, similar to dirname(1) or
File::Basename::dirname.  The dirname will end with a trailing slash
(except the "root" dir - see below).

NB: Returns the empty string for the "root" dir.

=item basename

Returns the "filename" part of the name, similar basename(1) or
File::Basename::basename (without passing a suffix to strip in either
case).  For dirs, the basename will end with a trailing slash (except
for the "root" dir - see below).

NB: Returns the empty string for the "root" dir.

=cut

Lintian::Path->mk_ro_accessors(
    qw(name owner group link type uid gid
      size date operm parent_dir dirname basename
      ));

=item children

Returns a list of children (as Lintian::Path objects) of this entry.
The list and its contents should not be modified.

NB: Returns the empty list for non-dir entries.

=cut

sub children {
    my ($self) = @_;
    return @{$self->{'_sorted_children'} };
}

=item child(BASENAME)

Returns the child named BASENAME if it is a child of this directory.
Otherwise, this method returns C<undef>.  Note if BASENAME has a
trailing slash, the child entry must be a directory.  If the child
exist, but is not a directory, C<undef> will be returned instead.

For non-dirs, this method always returns C<undef>.

Example:

  $dir_entry->child('foo') => $entry OR undef

  $dir_entry->child('foo/') => $dir_entry OR undef

=cut

sub child {
    my ($self, $basename) = @_;
    my $children = $self->{'children'};
    my ($child, $had_trailing_slash);

    # Remove the trailing slash (for dirs)
    if (substr($basename, -1, 1) eq '/') {
        $basename = substr($basename, 0, -1);
        $had_trailing_slash = 1;
    }
    return if not $children or not exists($children->{$basename});
    $child = $children->{$basename};
    # Only directories are allowed to be fetched with trailing slash.
    return if $had_trailing_slash and not $child->is_dir;
    return $child;
}

=item is_symlink

Returns a truth value if this entry is a symlink.

=item is_hardlink

Returns a truth value if this entry is a hardlink to a regular file.

NB: The target of a hardlink is always a regular file (and not a dir etc.).

=item is_dir

Returns a truth value if this entry is a dir.

NB: Unlike the "-d $dir" operator this will never return true for
symlinks, even if the symlink points to a dir.

=item is_file

Returns a truth value if this entry is a regular file (or a hardlink to one).

NB: Unlike the "-f $dir" operator this will never return true for
symlinks, even if the symlink points to a file (or hardlink).

=item is_regular_file

Returns a truth value if this entry is a regular file.

This is eqv. to $path->is_file and not $path->is_hardlink.

NB: Unlike the "-f $dir" operator this will never return true for
symlinks, even if the symlink points to a file.

=cut

sub is_symlink { return $_[0]->type eq 'l'; }
sub is_hardlink { return $_[0]->type eq 'h'; }
sub is_dir { return $_[0]->type eq 'd'; }
sub is_file { return $_[0]->type eq '-' || $_[0]->type eq 'h'; }
sub is_regular_file  { return $_[0]->type eq '-'; }

=item link_normalized

Returns the target of the link normalized against it's directory name.
If the link cannot be normalized or normalized path might escape the
package root, this method returns C<undef>.

NB: This method will return the empty string for links pointing to the
root dir of the package.

Only available on "links" (i.e. symlinks or hardlinks).  On non-links
this will croak.

I<Symlinks only>: If you want the symlink target as a L<Lintian::Path>
object, use the L<resolve_path|/resolve_path([PATH])> method with no
arguments instead.

=cut

sub link_normalized {
    my ($self) = @_;
    return $self->{'link_target'} if exists $self->{'link_target'};
    my $name = $self->name;
    my $link = $self->link;
    croak "$name is not a link" unless defined $link;
    my $dir = $self->dirname;
    # hardlinks are always relative to the package root
    $dir = '/' if $self->is_hardlink;
    my $target = normalize_pkg_path($dir, $link);
    $self->{'link_target'} = $target;
    return $target;
}

=item is_readable

Returns a truth value if the permission bits of this entry have
at least one bit denoting readability set (bitmask 0444).

=item is_writable

Returns a truth value if the permission bits of this entry have
at least one bit denoting writability set (bitmask 0222).

=item is_executable

Returns a truth value if the permission bits of this entry have
at least one bit denoting executability set (bitmask 0111).

=cut

sub _any_bit_in_operm {
    my ($self, $bitmask) = @_;
    return ($self->operm & $bitmask) ? 1 : 0;
}

sub is_readable   { return $_[0]->_any_bit_in_operm(0444); }
sub is_writable   { return $_[0]->_any_bit_in_operm(0222); }
sub is_executable { return $_[0]->_any_bit_in_operm(0111); }

=item file_info

Return the data from L<file(1)> if it has been collected.

Note this is only defined for files as Lintian only runs L<file(1)> on
files.

=cut

sub file_info {
    my ($self) = @_;
    my $file_info;
    if (my $file_info = $self->{'_file_info'}) {
        return $file_info;
    }
    $file_info = $self->{'_fs_info'}->_file_info($self);
    $self->{'_file_info'} = $file_info;
    return $file_info;
}

=item fs_path

Returns the path to this object on the file system, which must be a
regular file, a hardlink or a directory.

This method may fail if:

=over 4

=item * The object is neither a directory or a file-like object (e.g. a
named pipe).

=item * If the object is dangling symlink or the path traverses a symlink
outside the package root.

=back

To test if this is safe to call, if the target is (supposed) to be a:

=over 4

=item * file or hardlink then test with L</is_open_ok>.

=item * dir then assert L<resolve_path|/resolve_path([PATH])> returns a
defined entry, for which L</is_dir> returns a truth value.

=back

=cut

sub fs_path {
    my ($self) = @_;
    my $path = $self->_collect_path();
    $self->_check_access($path);
    return $path if $self->resolve_path->is_dir;
    $self->_check_open($path);
    return $path;
}

=item is_open_ok

Returns a truth value if it is safe to attempt open a read handle to
the underlying file object.

Returns a truth value if the path may be opened.

=cut

sub is_open_ok {
    my ($self) = @_;
    return $self->{'_is_open_ok'} if exists($self->{'_is_open_ok'});
    eval {
        my $path = $self->_collect_path();
        $self->_check_open($path);
    };
    return if $@;
    return 1;
}

sub _collect_path {
    my ($self) = @_;
    return $self->{'_fs_info'}->_underlying_fs_path($self);
}

sub _check_access {
    my ($self, $path) = @_;
    my $safe = 1;
    if (exists($self->{'_valid_path'})) {
        $safe = $self->{'_valid_path'};
    } else {
        my $resolvable = $self->resolve_path;
        $safe = 0 if not $resolvable;
    }
    if (not $safe) {
        $self->{'_valid_path'} = $self->{'_is_open_ok'} = 0;
        # NB: We are deliberately vague here to avoid suggesting
        # whether $path exists.  In some cases (e.g. lintian.d.o)
        # the output is readily available to wider public.
        confess('Attempt to access through broken or unsafe symlink:'. ' '
              . $self->name);
    }
    $self->{'_valid_path'} = 1;
    return 1;
}

sub _check_open {
    my ($self, $path) = @_;
    $self->_check_access($path);
    # Symlinks can point to a "non-file" object inside the
    # package root
    if ($self->is_file or ($self->is_symlink and -f $path)) {
        $self->{'_is_open_ok'} = 1;
        return 1;
    }
    $self->{'_is_open_ok'} = 0;
    confess("Attempt to open non-file (e.g. dir or pipe): $self");
}

sub _do_open {
    my ($self, $open_sub) = @_;
    my $path = $self->_collect_path();
    $self->_check_open($path);
    return $open_sub->($path);
}

=item open([LAYER])

Open and return a read handle to the file.  It optionally accepts the
LAYER argument.  If given it should specify the layer/discipline to
use when opening the file including the initial colon (e.g. ':raw').

Beyond regular issues with opening a file, this method may fail if:

=over

=item * The object is not a file-like object (e.g. a directory or a named pipe).

=item * If the object is dangling symlink or the path traverses a symlink
outside the package root.

=back

It is possible to test for these by using L</is_open_ok>.

=cut

sub open {
    my ($self, $layer) = @_;
    # Scoped autodie in here to avoid it overwriting our
    # method "open"
    $layer //= '';
    my $opener = sub {
        use autodie qw(open);
        open(my $fd, "<${layer}", $_[0]);
        return $fd;
    };
    return $self->_do_open($opener);
}

=item open_gz

Open a read handle to the file and decompress it as a GZip compressed
file.  This method may fail for the same reasons as L</open([LAYER])>.

The returned handle may be a pipe from an external process.

=cut

sub open_gz {
    my ($self) = @_;
    return $self->_do_open(\&Lintian::Util::open_gz);
}

=item file_contents

Return the file contents as a scalar.

This method may fail for the same reasons as L</open([LAYER])>.

=cut

sub file_contents {
    my ($self) = @_;
    my $fd = $self->open;
    return slurp_entire_file($fd);
}

=item root_dir

Return the root dir entry of this the path entry.

=cut

sub root_dir {
    my ($self) = @_;
    my $current = $self;
    while (my $next = $current->parent_dir) {
        $current = $next;
    }
    return $current;
}

sub _set_parent_dir {
    my ($self, $parent) = @_;
    weaken($self->{'parent_dir'} = $parent);
    return 1;
}

=item resolve_path([PATH])

Resolve PATH relative to this path entry.

If PATH starts with a slash and the file hierarchy has a well-defined
root directory, then PATH will instead be resolved relatively to the
root dir.  If the file hierarchy does not have a well-defined root dir
(e.g. for source packages), this method will return C<undef>.

If PATH is omitted, then the entry is resolved and the target is
returned if it is valid.  Except for symlinks, all entries always
resolve to themselves.  NB: hardlinks also resolve as themselves.

It is an error to attempt to resolve a PATH against a non-directory
and non-symlink entry - as such resolution would always fail
(i.e. foo/../bar is an invalid path unless foo is a directory or a
symlink to a dir).


The resolution takes symlinks into account and following them provided
that the target path is valid (and can be followed safely).  If the
path is invalid or circular (symlinks), escapes the root directory or
follows an unsafe symlink, the method returns C<undef>.  Otherwise, it
returns the path entry that denotes the target path.


If PATH contains at least one path segment and ends with a slash, then
the resolved path will end in a directory (or fail).  Otherwise, the
resolved PATH can end in any entry I<except> a symlink.

Examples:

  $symlink_entry->resolve_path => $nonsymlink_entry OR undef

  $x->resolve_path => $x

  For directory or symlink entries (dol), you can also resolve a path:

  $dol_entry->resolve_path('some/../where') => $nonsymlink_entry OR undef

  # Note the trailing slash
  $dol_entry->resolve_path('some/../where/') => $dir_entry OR undef

=cut

sub resolve_path {
    my ($self, $path_str) = @_;
    my $current = $self;
    my (@queue, %traversed_links, $had_trailing_slash);
    my $fs_info = $self->{'_fs_info'};

    if (defined($path_str) and ref($path_str) ne q{}) {
        croak('resolve_path only accepts string arguments');
    }

    $path_str //= '';

    if (not $self->is_dir and not $self->is_symlink) {
        return $self if $path_str eq '';
        croak("Path \"$self\" is not a directory or a symlink");
    }

    $path_str =~ s{//++}{/}g;
    $had_trailing_slash = $path_str =~ s{/\z}{};

    if ($path_str =~ s{^/}{} or ($path_str eq q{} and $had_trailing_slash)) {
        # Find the root entry
        return if not $fs_info->has_anchored_root_dir;
        $current = $self->root_dir;
        return $current if $path_str eq q{};
    }
    if ($path_str eq q{} or $path_str eq q{.}) {
        if (not $current->is_symlink) {
            return $current if ($current->is_dir or not $had_trailing_slash);
            return;
        }
    } else {
        # Add all segments to the queue
        @queue = split(m{/}, $path_str);
    }

    if ($had_trailing_slash) {
        # If there is a trailing slash, then the final path segment
        # must be a directory.
        push(@queue, q{.});
    }

    while (1) {
        my $target;
        if ($current->is_symlink) {
            # Stop if we already traversed this link.
            return if $traversed_links{$current->name}++;
            my $link_text = $current->link;
            $link_text =~ s{//++}{/}g;
            if ($link_text eq q{/} or $link_text =~ s{^/}{}) {
                return if not $fs_info->has_anchored_root_dir;
                $current = $current->root_dir;
            } else {
                $current = $current->parent_dir;
            }
            $link_text =~ s{/\z}{};
            return if $link_text eq q{};
            unshift(@queue, split(m@/@, $link_text));
        }
        last if not @queue;
        $target = shift(@queue);

        if ($target eq q{..}) {
            $current = $current->parent_dir;
            return unless $current;
        } else {
            # if there is segment (even a "."), then the current path
            # must be a directory.
            return if not $current->is_dir;
            if ($target ne q{.}) {
                $current = $current->child($target);
                return if not $current;
            }
        }
    }
    return $current;
}

### OVERLOADED OVERATORS ###

# overload apparently does not like the mk_ro_accessor, so use a level
# of indirection

sub _as_regex_ref {
    my ($self) = @_;
    my $name = $self->name;
    return qr{ \Q$name\E }xsm;
}

sub _as_string {
    my ($self) = @_;
    return $self->name;
}

sub _bool {
    # Always true (used in "if ($info->index('some/path')) {...}")
    return 1;
}

sub _bool_not {
    my ($self) = @_;
    return !$self->_bool;
}

sub _str_cmp {
    my ($self, $str, $swap) = @_;
    return $str cmp $self->name if $swap;
    return $self->name cmp $str;
}

sub _str_concat {
    my ($self, $str, $swap) = @_;
    return $str . $self->name if $swap;
    return $self->name . $str;
}

sub _str_eq {
    my ($self, $str) = @_;
    return $self->name eq $str;
}

sub _str_ne {
    my ($self, $str) = @_;
    return $self->name ne $str;
}

=back

=head1 AUTHOR

Originally written by Niels Thykier <niels@thykier.net> for Lintian.

=head1 SEE ALSO

lintian(1), Lintian::Collect(3), Lintian::Collect::Binary(3),
Lintian::Collect::Source(3)

=cut

1;

# Local Variables:
# indent-tabs-mode: nil
# cperl-indent-level: 4
# End:
# vim: syntax=perl sw=4 sts=4 sr et

