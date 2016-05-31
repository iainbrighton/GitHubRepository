## GitHubRepository Module ##
The __GitHubRepository__ module provides a single `Install-GitHubRepository` cmdlet that will download and extract
PowerShell modules hosted in a GitHub repository. GitHub development branches often include new and unreleased
functionality that may need to be downloaded directly from GitHub until they are officially released. Manually
downloading, unblocking and renaming directories is a slow and cumbersome process; no longer!

The `Install-GitHubRepository` cmdlet is primarily intended to help bootstrap the installation of Powershell modules
and DSC resources that have not been (yet) published to the [PowerShell Gallery](https://www.powershellgallery.com/)
or have been updated on a development branch and are needed for testing purposes.

As an example, the development branch of the Microsoft-owned Active Directory DSC resource can simply be installed on
the local machine by running:
```powershell
Install-GitHubRepository -Owner PowerShell -Repository xActiveDirectory -Branch dev
```
By default _any existing files_ are not removed or overwritten. To force the removal of an existing PowerShell modules,
specify the `-Clean` switch. This option is normally specified when an existing module might already be installed on
the system.
```powershell
Install-GitHubRepository -Owner PowerShell -Repository xActiveDirectory -Branch dev -Clean
```
### Overriding the installation directory
By default all modules are installed into the `$env:ProgramFiles\WindowsPowershell\Modules` directory which is
required for DSC resources. __Note: this will typically require Administrator rights__.

If you need to install a GitHub-published module into an alternative path, override the target directory with the
`-DestinationPath` parameter. For example, to install the [PhatGit](https://github.com/iainbrighton/PhatGit) module
into the current user's module path, use the following command:
```powershell
Install-GitHubRepository -Owner IainBrighton -Repository PhatGit -DestinationPath $env:UserProfile:\Documents\WindowsPowershell\Modules
```
### Overriding the module name
If a GitHub repository name does not match the desired module directory, for example the repository name does not match
a module's name, then the destination folder can be overridden with the `-OverrideRepository` switch.

This was the case with the [VirtualEngineLab](https://github.com/VirtualEngine/Lab) module. The VirtualEngineLab
module's GitHub repository name was 'Lab', but the module needed to be downloaded and extracted into the
'VirtualEngineLab' directory, not the 'Lab' directory. The following command downloads and registers the module in the
correct directory:
```powershell
Install-GitHubRepository -Owner VirtualEngine -Repository Lab -OverrideRepository VirtualEngineLab
```
### Syntax
```
NAME
    Install-GitHubRepository

SYNOPSIS
    Downloads, extracts and installs a repository directly from GitHub.

SYNTAX
    Install-GitHubRepository -Owner <String> -Repository <String> [-Branch <String>] [-DestinationPath <String>]
        [-OverrideRepository <String>] [-Clean] [<CommonParameters>]

    Install-GitHubRepository -Owner <String> -Repository <String> [-Branch <String>] [-DestinationPath <String>]
        [-OverrideRepository <String>] [-Force] [<CommonParameters>]


DESCRIPTION
    The Install-GitHubRepository cmdlet will download and extract a GitHub repository. This will typically be
    development PowerShell modules or DSC resources.

    Install-GitHubRepository is primarily intended to help bootstrap the installation of Powershell modules and DSC
    resources that have not (yet) been published to the PowerShell Gallery or have been updated on a development branch
    and are needed for testing purposes.


PARAMETERS
    -Owner <String>
        Specifies the owner of the GitHub repository from whom to download the module.

        Required?                    true
        Position?                    1
        Default value
        Accept pipeline input?       true (ByPropertyName)
        Accept wildcard characters?  false

    -Repository <String>
        Specifies the GitHub repository name to download.

        Required?                    true
        Position?                    2
        Default value
        Accept pipeline input?       true (ByPropertyName)
        Accept wildcard characters?  false

    -Branch <String>
        Specifies the specific Git repository branch to download. If this is not specified it defaults to the 'master'
        branch.

        Required?                    false
        Position?                    3
        Default value                master
        Accept pipeline input?       false
        Accept wildcard characters?  false

    -DestinationPath <String>
        Specifies the path to the folder in which you want the command to save GitHub repository. Enter the path to a
        folder, but do not specify a file name or file name extension. If this parameter is not specified, it defaults
        to the '$env:ProgramFiles\WindowsPowershell\Modules' directory.

        Required?                    false
        Position?                    4
        Default value                "$env:ProgramFiles\WindowsPowershell\Modules"
        Accept pipeline input?       false
        Accept wildcard characters?  false

    -OverrideRepository <String>
        Specifies overriding the repository name when it's expanded to disk. Use this parameter when the extracted Zip
        file path does not meet your requirements, i.e. when the repository name does not match the Powershell module
        name.

        Required?                    false
        Position?                    5
        Default value
        Accept pipeline input?       false
        Accept wildcard characters?  false

    -Force [<SwitchParameter>]
        Forces the extraction of files from an archive file. By default, any files that exist on the local file system
        are not overwritten.

        Required?                    false
        Position?                    named
        Default value                False
        Accept pipeline input?       false
        Accept wildcard characters?  false
        
    -Clean [<SwitchParameter>]
        Removes the existing repository folder from the local file system before extracting the archive. This ensures
        that local repository matches the source GitHub repository. Note: this should only be used with PowerShell
        module/DSC repositories.

        Required?                    false
        Position?                    named
        Default value                False
        Accept pipeline input?       true (ByPropertyName)
        Accept wildcard characters?  false

    <CommonParameters>
        This cmdlet supports the common parameters: Verbose, Debug,
        ErrorAction, ErrorVariable, WarningAction, WarningVariable,
        OutBuffer, PipelineVariable, and OutVariable. For more information, see
        about_CommonParameters (http://go.microsoft.com/fwlink/?LinkID=113216).

INPUTS

OUTPUTS
    System.IO.DirectoryInfo
```
