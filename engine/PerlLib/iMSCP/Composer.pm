=head1 NAME

 iMSCP::Composer - i-MSCP Composer packages installer

=cut

# i-MSCP - internet Multi Server Control Panel
# Copyright (C) 2010-2017 by Laurent Declercq <l.declercq@nuxwin.com>
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.

package iMSCP::Composer;

use strict;
use warnings;
use iMSCP::Debug;
use iMSCP::Dialog;
use iMSCP::Dir;
use iMSCP::Execute;
use iMSCP::EventManager;
use iMSCP::File;
use iMSCP::Getopt;
use iMSCP::Stepper;
use iMSCP::TemplateParser;
use parent 'Common::SingletonClass';

=head1 DESCRIPTION

 Composer packages installer for i-MSCP.

=head1 PUBLIC METHODS

=over 4

=item registerPackage( $package [, $packageVersion = 'dev-master' ] )

 Register the given composer package for installation

 Param string $package Package name
 Param string $packageVersion OPTIONAL Package version
 Return int 0

=cut

sub registerPackage
{
    my ($self, $package, $packageVersion) = @_;

    $packageVersion ||= 'dev-master';
    push @{$self->{'packages'}}, "        \"$package\": \"$packageVersion\"";
    0;
}

=back

=head1 PRIVATE METHODS

=over 4

=item _init( )

 Initialize instance

 Return iMSCP::Composer

=cut

sub _init
{
    my ($self) = @_;

    $self->{'packages'} = [ ];
    $self->{'packages_dir'} = "$main::imscpConfig{'IMSCP_HOMEDIR'}/packages";
    $self->{'su_cmd_pattern'} = "su -l $main::imscpConfig{'IMSCP_USER'} -s /bin/bash -c %s";
    $self->{'php_cmd_prefix'} = "php -d date.timezone=$main::imscpConfig{'TIMEZONE'} -d allow_url_fopen=1 "
        ."-d suhosin.executor.include.whitelist=phar";

    iMSCP::EventManager->getInstance( )->register(
        'afterSetupPreInstallPackages',
        sub {

            my $rs = $self->_cleanPackageCache( ) if iMSCP::Getopt->cleanPackageCache;
            $rs ||= iMSCP::Dir->new( dirname => $self->{'packages_dir'} )->make(
                {
                    user => $main::imscpConfig{'IMSCP_USER'},
                    group => $main::imscpConfig{'IMSCP_GROUP'},
                    mode => 0755
                }
            );

            startDetail;

            $rs ||= step(
                sub {
                    unless (iMSCP::Getopt->skipPackageUpdate
                        && -x "$main::imscpConfig{'IMSCP_HOMEDIR'}/composer.phar"
                    ) {
                        $rs = $self->_getComposer( );
                        return $rs if $rs;
                    }
                    0;
                },
                'Installing composer.phar from http://getcomposer.org', 3, 1
            );
            $rs ||= step(
                sub { iMSCP::Getopt->skipPackageUpdate ? $self->_checkRequirements( ) : 0; },
                'Checking composer package requirements', 3, 2
            );

            if (iMSCP::Getopt->skipPackageUpdate) {
                endDetail;
                return $rs;
            };

            $rs ||= step(
                sub { $self->_installPackages( ); },
                'Installing/Updating composer packages from Github', 3, 3
            );

            endDetail;
            return $rs;
        }
    );

    $self;
}

=item _getComposer( )

 Get composer.phar

 Return 0 on success, other on failure

=cut

sub _getComposer
{
    my ($self) = @_;

    my $msgHeader = "Installing/Updating composer.phar from http://getcomposer.org\n\n";
    my $msgFooter = "\nDepending on your connection, this may take few seconds...";
    my ($rs, $stderr) = (0, undef);

    unless (-f "$main::imscpConfig{'IMSCP_HOMEDIR'}/composer.phar") {
        $rs = executeNoWait(
            sprintf(
                $self->{'su_cmd_pattern'},
                escapeShell( "curl -s http://getcomposer.org/installer | $self->{'php_cmd_prefix'}" )
            ),
            (iMSCP::Getopt->noprompt && iMSCP::Getopt->verbose
                ? undef : sub { step( undef, $msgHeader.(shift).$msgFooter, 3, 1 ); }
            ),
            sub { $stderr .= shift; }
        );
    } else {
        $rs = executeNoWait(
            sprintf(
                $self->{'su_cmd_pattern'},
                escapeShell(
                    "$self->{'php_cmd_prefix'} $main::imscpConfig{'IMSCP_HOMEDIR'}/composer.phar self-update "
                        ."--clean-backups --stable --no-ansi --no-interaction"
                )
            ),
            (iMSCP::Getopt->noprompt && iMSCP::Getopt->verbose
                ? undef : sub { step( undef, "$msgHeader".(shift).$msgFooter, 3, 1 ); }
            ),
            sub { $stderr .= shift; }
        );
    }

    error( sprintf( "Couldn't install/update composer.phar: %s", $stderr || 'Unknown error' ) ) if $rs;
    $rs;
}

=item _checkRequirements( )

 Check package version requirements

 Return int 0 if all requirements are met, 1 otherwise

=cut

sub _checkRequirements
{
    my ($self) = @_;

    return 0 unless -d $self->{'packages_dir'};

    my $msgHeader = "Checking composer package requirements\n\n";
    my $stderr;

    for(@{$self->{'packages'}}) {
        my ($package, $version) = $_ =~ /"(.*)":\s*"(.*)"/;
        my $msg = $msgHeader."Checking package $package ($version)\n\n";

        my $rs = executeNoWait(
            sprintf(
                $self->{'su_cmd_pattern'},
                escapeShell(
                    "$self->{'php_cmd_prefix'} $main::imscpConfig{'IMSCP_HOMEDIR'}/composer.phar show --no-ansi ".
                        "--no-interaction --working-dir=$self->{'packages_dir'} $package $version"
                )
            ),
            (iMSCP::Getopt->noprompt && iMSCP::Getopt->verbose
                ? undef : sub { step( undef, $msg, 3, 2 ); }
            ),
            sub { $stderr .= shift; }
        );
        if ($rs) {
            error( sprintf( "Package %s (%s) not found. Please retry without the '-a' option.", $package, $version ) );
            return 1;
        }
    }

    0;
}

=item _installPackages( )

 Install or update packages

 Return 0 on success, other on failure

=cut

sub _installPackages
{
    my ($self) = @_;

    my $rs = $self->_buildComposerFile( );
    return $rs if $rs;

    my $msgHeader = "Installing/Updating composer packages from Github\n\n";
    my $msgFooter = "\nDepending on your connection, this may take few seconds...";

    # Note: Any progress/status info goes to stderr (See https://github.com/composer/composer/issues/3795)
    $rs = executeNoWait(
        sprintf(
            $self->{'su_cmd_pattern'},
            escapeShell(
                "$self->{'php_cmd_prefix'} $main::imscpConfig{'IMSCP_HOMEDIR'}/composer.phar update --no-ansi "
                    ."--no-interaction --working-dir=$self->{'packages_dir'}"
            )
        ),
        sub { },
        (iMSCP::Getopt->noprompt && iMSCP::Getopt->verbose
            ? undef : sub { step( undef, $msgHeader.(shift).$msgFooter, 3, 3 ); }
        )
    );

    error( "Couldn't install/update i-MSCP packages from GitHub" ) if $rs;
    $rs;
}

=item _buildComposerFile( )

 Build composer.json file

 Return 0 on success, other on failure

=cut

sub _buildComposerFile
{
    my ($self) = @_;

    my $tpl = <<'TPL';
{
    "name": "imscp/packages",
    "description": "i-MSCP composer packages",
    "licence": "GPL-2.0+",
    "require": {
{PACKAGES}
    },
    "config": {
        "preferred-install": "dist",
        "process-timeout": 2000,
        "discard-changes": true
    },
    "minimum-stability": "dev"
}
TPL

    my $file = iMSCP::File->new( filename => "$self->{'packages_dir'}/composer.json" );
    my $rs ||= $file->set( process( { PACKAGES => join ",\n", @{$self->{'packages'}} }, $tpl ) );
    $rs ||= $file->save( );
}

=item _cleanPackageCache( )

 Clear composer package cache

 Return 0 on success, other on failure

=cut

sub _cleanPackageCache
{
    my ($self) = @_;

    my $rs = iMSCP::Dir->new( dirname => "$main::imscpConfig{'IMSCP_HOMEDIR'}/.cache" )->remove( );
    $rs ||= iMSCP::Dir->new( dirname => "$main::imscpConfig{'IMSCP_HOMEDIR'}/.composer" )->remove( );
    $rs ||= iMSCP::Dir->new( dirname => $self->{'packages_dir'} )->remove( );
}

=back

=head1 AUTHOR

 Laurent Declercq <l.declercq@nuxwin.com>

=cut

1;
__END__
