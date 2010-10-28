use strict;
use warnings;
package Apache2::Layer;
# ABSTRACT: Layers for DocumentRoot

use Apache2::Const -compile => qw(
    ACCESS_CONF RSRC_CONF
    TAKE1 ITERATE
    OK DECLINED
);
use APR::Const -compile => qw(FINFO_NORM);

use Apache2::CmdParms ();
use Apache2::Module ();
use Apache2::Directive ();
use Apache2::RequestRec ();
use Apache2::RequestUtil ();
use Apache2::RequestIO ();
use Apache2::ServerRec ();
use Apache2::ServerUtil ();
use APR::Finfo ();

use File::Spec ();

my @directives = (
    {
        name         => 'DocumentRootLayers',
        func         => __PACKAGE__ . '::_DocumentRootLayersParam',
        req_override => Apache2::Const::RSRC_CONF | Apache2::Const::ACCESS_CONF,
        args_how     => Apache2::Const::ITERATE,
        errmsg       => 'DocumentRootLayers DirPath1 [DirPath2 ... [DirPathN]]',
    },
    {
        name         => 'EnableDocumentRootLayers',
        func         => __PACKAGE__ . '::_EnableDocumentRootLayersParam',
        req_override => Apache2::Const::RSRC_CONF | Apache2::Const::ACCESS_CONF,
        args_how     => Apache2::Const::TAKE1,
        errmsg       => 'EnableDocumentRootLayers On|Off',
    },
);
Apache2::Module::add(__PACKAGE__, \@directives);
Apache2::ServerUtil->server->push_handlers(PerlTransHandler => ['Apache2::Layer::handler'] );

sub _merge_cfg {
    return bless { %{$_[0]}, %{$_[1]} }, ref $_[0];
}

sub DIR_MERGE { _merge_cfg(@_) }
sub SERVER_MERGE { _merge_cfg(@_) }

{
    my @forbidden = qw(
        <Directory
        <DirectoryMatch
        <Files
        <FilesMatch
    );

    sub _check_cmd_context {
        my $directive = shift;

        my $cmd = $directive->directive;

        while ( my $parent = $directive->parent ) {
            for ( @forbidden ) {
                die "$cmd not allowed within $_ ...>\n"
                    if $parent->directive eq $_;
            }
            $directive = $parent;
        }

        return 0;
    }
}

sub _DocumentRootLayersParam {
    my ($self, $params, $path) = @_;

    _check_cmd_context($params->directive);

    push @{ $self->{DocumentRootLayers} }, $path;
}

sub _EnableDocumentRootLayersParam {
    my ($self, $params, $flag) = @_;

    _check_cmd_context($params->directive);

    die "EnableDocumentRootLayers On|Off, not $flag\n"
        unless $flag =~ /^(?:On|Off)$/;

    $self->{DocumentRootLayersEnabled} = $flag eq 'On' ? 1 : 0;
}

sub handler {
    my $r = shift;

    my $dir_cfg = Apache2::Module::get_config(
        __PACKAGE__, $r->server, $r->per_dir_config
    );

    return Apache2::Const::DECLINED
        unless $dir_cfg->{DocumentRootLayersEnabled};

    if ( my $paths = $dir_cfg->{DocumentRootLayers} ) {
        for my $dir ( @$paths ) {
            my $file = File::Spec->canonpath(
                File::Spec->catfile(
                    File::Spec->file_name_is_absolute($dir) ?
                        $dir : File::Spec->catdir( $r->document_root, $dir ),
                    $r->uri
                )
            );

            if ( my $finfo = eval {
                APR::Finfo::stat($file, APR::Const::FINFO_NORM, $r->pool)
            } ) {
                $r->push_handlers(PerlMapToStorageHandler => sub {
                    my $r = shift;
                    $r->filename($file);
                    $r->finfo($finfo);
                    return Apache2::Const::DECLINED;
                });

                return Apache2::Const::DECLINED;
            }
        }
    }

    return Apache2::Const::DECLINED;
}

=head1 SYNOPSIS

    # in httpd.conf
    DocumentRoot "/usr/local/htdocs"

    # load module
    PerlLoadModule Apache2::Layer

    # enable layers for whole server
    EnableDocumentRootLayers On

    # paths are relative to DocumentRoot
    DocumentRootLayers layered/christmas layered/promotions

    <VirtualHost *:80>
        ...
        # layers enabled for this vhost
    </VirtualHost>

    <VirtualHost *:80>
        ...
        DocumentRoot "/usr/local/vhost2"

        # disabled by default
        EnableDocumentRootLayers Off

        <LocationMatch "\.png$">
            # layer images only
            EnableDocumentRootLayers On
            DocumentRootLayers images_v3 images_v2
        </LocationMatch>

    </VirtualHost>

    <VirtualHost *:80>
        ...
        PerlOptions +MergeHandlers
        PerlTransHandler My::Other::Handler
    </VirtualHost>



=head1 DESCRIPTION

Create multiple layers to allow incremental content modifications.

If file was found in layered directory it will be used instead of one from
C<DocumentRoot>.

Loaded module adds itself as C<PerlTransHandler> and
C<PerlMapToStorageHandler>, so please remember to use

    PerlOptions +MergeHandlers

if you want to define your own handlers for those phases.

=head1 DIRECTIVES

L<Apache2::Layer> needs to be loaded via C<PerlLoadModule> due to use of
following directives:

=head2 EnableDocumentRootLayers

    Syntax:   EnableDocumentRootLayers On|Off
    Default:  EnableDocumentRootLayers Off
    Context:  server config, virtual host, <Location*

Enable use of L<"DocumentRootLayers">.

=head2 DocumentRootLayers

    Syntax:   DocumentRootLayers dir-path1 [dir-path2 ... dir-pathN]
    Context:  server config, virtual host, <Location*

Specify content layers to be used on top of C<DocumentRoot>.

If the I<dir-path*> is not absolute it is assumed to be relative to
C<DocumentRoot>.

Directories are searched in order specified and first one containing the file
is used.

If file does not exists in any of them module falls back to C<DocumentRoot>.

=head1 SEE ALSO

Module was created as a result of upgrade existing application from mod_perl1
to mod_perl2 and is a replacement for L<Apache::Layer>.

=cut

1;

