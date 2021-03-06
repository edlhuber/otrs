# --
# Copyright (C) 2001-2017 OTRS AG, http://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::Output::HTML::NavBar::ModuleAdmin;

use parent 'Kernel::Output::HTML::Base';

use strict;
use warnings;

our @ObjectDependencies = (
    'Kernel::Config',
    'Kernel::Output::HTML::Layout',
    'Kernel::System::Group',
    'Kernel::System::JSON',
    'Kernel::System::User',
);

sub Run {
    my ( $Self, %Param ) = @_;

    # get layout object
    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');

    # only show it on admin start screen
    return '' if $LayoutObject->{Action} ne 'Admin';

    # get config object
    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');

    # generate manual link
    my $ManualVersion = $ConfigObject->Get('Version');
    $ManualVersion =~ m{^(\d{1,2}).+};
    $ManualVersion = $1;

    # get all Frontend::Module
    my %NavBarModule;

    my $NavigationModule = $ConfigObject->Get('Frontend::NavigationModule') || {};

    MODULE:
    for my $Module ( sort keys %{$NavigationModule} ) {
        my %Hash = %{ $NavigationModule->{$Module} };

        next MODULE if !$Hash{Name};

        if ( $Hash{Module} eq 'Kernel::Output::HTML::NavBar::ModuleAdmin' ) {

            # check permissions (only show accessable modules)
            my $Shown       = 0;
            my $GroupObject = $Kernel::OM->Get('Kernel::System::Group');

            for my $Permission (qw(GroupRo Group)) {

                # no access restriction
                if (
                    ref $Hash{GroupRo} eq 'ARRAY'
                    && !scalar @{ $Hash{GroupRo} }
                    && ref $Hash{Group} eq 'ARRAY'
                    && !scalar @{ $Hash{Group} }
                    )
                {
                    $Shown = 1;
                }

                # array access restriction
                elsif ( $Hash{$Permission} && ref $Hash{$Permission} eq 'ARRAY' ) {
                    for my $Group ( @{ $Hash{$Permission} } ) {
                        my $HasPermission = $GroupObject->PermissionCheck(
                            UserID    => $Self->{UserID},
                            GroupName => $Group,
                            Type      => $Permission eq 'GroupRo' ? 'ro' : 'rw',
                        );
                        if ($HasPermission) {
                            $Shown = 1;
                        }
                    }
                }
            }
            next MODULE if !$Shown;

            my $Key = sprintf( "%07d", $Hash{NavBarModule}->{Prio} || 0 );
            COUNT:
            for ( 1 .. 51 ) {
                if ( $NavBarModule{$Key} ) {
                    $Hash{NavBarModule}->{Prio}++;
                    $Key = sprintf( "%07d", $Hash{NavBarModule}->{Prio} );
                }
                if ( !$NavBarModule{$Key} ) {
                    last COUNT;
                }
            }
            $NavBarModule{$Key} = {
                'Frontend::Module' => $Module,
                %Hash,
                %{ $Hash{NavBarModule} },
            };
        }
    }

    # get modules which were marked as favorite by the current user
    my %UserPreferences = $Kernel::OM->Get('Kernel::System::User')->GetPreferences(
        UserID => $Self->{UserID},
    );
    my @Favourites;
    my @FavouriteModules;
    my $PrefFavourites = $Kernel::OM->Get('Kernel::System::JSON')->Decode(
        Data => $UserPreferences{AdminNavigationBarFavourites},
    ) || [];

    @Favourites = sort {
        $LayoutObject->{LanguageObject}->Translate( $a->{Name} )
            cmp $LayoutObject->{LanguageObject}->Translate( $b->{Name} )
    } @Favourites;

    my @ModuleGroups;
    my $ModuleGroupsConfig = $ConfigObject->Get('Frontend::AdminModuleGroups');

    # get all registered groups
    for my $Group ( sort keys %{$ModuleGroupsConfig} ) {
        for my $Key ( sort keys %{ $ModuleGroupsConfig->{$Group} } ) {
            push @ModuleGroups, {
                'Key'   => $Key,
                'Order' => $ModuleGroupsConfig->{$Group}->{$Key}->{Order},
                'Title' => $ModuleGroupsConfig->{$Group}->{$Key}->{Title},
            };
        }
    }

    # sort groups by order number
    @ModuleGroups = sort { $a->{Order} <=> $b->{Order} } @ModuleGroups;

    my %Modules;
    ITEMS:
    for my $Item ( sort keys %NavBarModule ) {

        # dont show the admin overview as a tile
        next ITEMS if ( $NavBarModule{$Item}->{'Link'} && $NavBarModule{$Item}->{'Link'} eq 'Action=Admin' );

        if ( grep { $_ eq $NavBarModule{$Item}->{'Frontend::Module'} } @{$PrefFavourites} ) {
            push @Favourites,       $NavBarModule{$Item};
            push @FavouriteModules, $NavBarModule{$Item}->{'Frontend::Module'};
            $NavBarModule{$Item}->{IsFavourite} = 1;
        }

        # add the item to its Block
        my $Block = $NavBarModule{$Item}->{'Block'} || 'Misc';
        if ( !grep { $_->{Key} eq $Block } @ModuleGroups ) {
            $Block = 'Misc';
        }
        push @{ $Modules{$Block} }, $NavBarModule{$Item};
    }

    $LayoutObject->Block(
        Name => 'AdminNavBar',
        Data => {
            ManualVersion => $ManualVersion,
            Items         => \%Modules,
            Groups        => \@ModuleGroups,
            Favourites    => \@Favourites,
        },
    );

    $LayoutObject->AddJSData(
        Key   => 'Favourites',
        Value => \@FavouriteModules,
    );

    my $Output = $LayoutObject->Output(
        TemplateFile => 'AdminNavigationBar',
        Data         => \%Param,
    );

    return $Output;
}

1;
