$localized = data {
ConvertFrom-StringData @'
    ResolvedDestinationPath     = Resolved destination path '{0}'.
    ResolvedSourcePath          = Resolved source path '{0}'.
    ExpandingZipArchive         = Expanding Zip archive '{0}'.
    CreatingDirectory           = Creating target directory '{0}'.
    ExtractingZipArchiveEntry   = Extracting Zip archive entry '{0}'.
    ClosingZipArchive           = Closing Zip archive '{0}'.
    CleaningRepositoryDirectory = Cleaning repository directory '{0}'.

    TargetFileExistsWarning     = Target file '{0}' already exists.

    InvalidDestinationPathError = Invalid destination path '{0}' specified.
'@
}

function ExpandZipArchive {
<#
    .SYNOPSIS
        Extracts a GitHub Zip archive.
    .NOTES
        This is an internal function and should not be called directly.
    .LINK
        This function is derived from the VirtualEngine.Compression (https://github.com/VirtualEngine/Compression) module.
    .OUTPUTS
        A System.IO.FileInfo object for each extracted file.
#>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess','')]
    [OutputType([System.IO.FileInfo])]
    param (
        # Source path to the Zip Archive.
        [Parameter(Mandatory, ValueFromPipelineByPropertyName, Position = 0)] [ValidateNotNullOrEmpty()]
        [Alias('PSPath','FullName')] [System.String[]] $Path,
        
        # Destination file path to extract the Zip Archive item to.
        [Parameter(Mandatory, ValueFromPipelineByPropertyName, Position = 1)] [ValidateNotNullOrEmpty()]
        [System.String] $DestinationPath,
        
        # GitHub repository name
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)] [ValidateNotNullOrEmpty()]
        [System.String] $Repository,
        
        # GitHub repository branch name
        [Parameter(ValueFromPipelineByPropertyName, Position = 2)] [ValidateNotNullOrEmpty()]
        [System.String] $Branch = 'master',

        [Parameter(ValueFromPipelineByPropertyName)] [ValidateNotNullOrEmpty()]
        [System.String] $OverrideRepository,
        
        # Overwrite existing files
        [Parameter(ValueFromPipelineByPropertyName)]
        [System.Management.Automation.SwitchParameter] $Force,
        
        ## Remove root folders/files in archive from destination path.
        [Parameter(ValueFromPipelineByPropertyName)]
        [System.Management.Automation.SwitchParameter] $Clean
    )
    begin {
        ## Validate destination path      
        if (-not (Test-Path -Path $DestinationPath -IsValid)) {
            throw ($localized.InvalidDestinationPathError -f $DestinationPath);
        }
        $DestinationPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($DestinationPath);
        Write-Verbose ($localized.ResolvedDestinationPath -f $DestinationPath);
        [Ref] $null = NewDirectory -Path $DestinationPath;
        foreach ($pathItem in $Path) {
            foreach ($resolvedPath in $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($pathItem)) {
                Write-Verbose ($localized.ResolvedSourcePath -f $resolvedPath);
                $LiteralPath += $resolvedPath;
            }
        }
        ## If all tests passed, load the required .NET assemblies
        Write-Debug 'Loading ''System.IO.Compression'' .NET binaries.';
        Add-Type -AssemblyName 'System.IO.Compression';
        Add-Type -AssemblyName 'System.IO.Compression.FileSystem';
    } # end begin
    process {
        if ($Clean) {
            ## Remove repository directory before expanding any items..
            $repositoryPath = Join-Path -Path $DestinationPath -ChildPath $Repository;
            if ($OverrideRepository) {
                $repositoryPath = Join-Path -Path $DestinationPath -ChildPath $OverrideRepository;
            }
            Write-Verbose ($localized.CleaningRepositoryDirectory -f $repositoryPath);
            if (Test-Path -Path $repositoryPath -PathType Container) {
                Remove-Item -Path $repositoryPath -Force -Recurse -ErrorAction Stop;
            }
        }

        foreach ($pathEntry in $LiteralPath) {
            try {
                Write-Verbose ($localized.ExpandingZipArchive -f $pathEntry);
                $zipArchive = [System.IO.Compression.ZipFile]::OpenRead($pathEntry);
                $expandZipArchiveItemParams = @{
                    InputObject = [ref] $zipArchive.Entries;
                    DestinationPath = $DestinationPath;
                    Repository = $Repository;
                    Branch = $Branch;
                    Force = $Force;
                }
                if ($OverrideRepository) {
                    $expandZipArchiveItemParams['OverrideRepository'] = $OverrideRepository;
                }
                ExpandZipArchiveItem @expandZipArchiveItemParams;
            } # end try
            catch {
                Write-Error $_.Exception;
            }
            finally {
                ## Close the file handle
                CloseZipArchive;
            }
        } # end foreach
    } # end process
} #end function ExpandZipArchive

function ExpandZipArchiveItem {
<#
    .SYNOPSIS
        Extracts file(s) from a GitHub Zip archive.
    .NOTES
        This is an internal function and should not be called directly.
    .LINK
        This function is derived from the VirtualEngine.Compression (https://github.com/VirtualEngine/Compression) module.
    .OUTPUTS
        A System.IO.FileInfo object for each extracted file.
#>
    [CmdletBinding(DefaultParameterSetName='Path', SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([System.IO.FileInfo])]
    param (
        # Reference to Zip archive item.
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true, Position = 0, ParameterSetName = 'InputObject')]
        [ValidateNotNullOrEmpty()] [System.IO.Compression.ZipArchiveEntry[]] [Ref] $InputObject,

        # Destination file path to extract the Zip Archive item to.
        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true, Position = 1)]
        [ValidateNotNullOrEmpty()] [System.String] $DestinationPath,

        # GitHub repository name
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)] [System.String] $Repository,

        # GitHub repository branch name
        [Parameter(ValueFromPipelineByPropertyName)] [ValidateNotNullOrEmpty()] [System.String] $Branch = 'master',

        ## Override repository name
        [Parameter(ValueFromPipelineByPropertyName)] [ValidateNotNullOrEmpty()] [System.String] $OverrideRepository,
        
        # Overwrite existing physical filesystem files
        [Parameter(ValueFromPipelineByPropertyName)]
        [System.Management.Automation.SwitchParameter] $Force
    )
    begin {
        Write-Debug 'Loading ''System.IO.Compression'' .NET binaries.';
        Add-Type -AssemblyName 'System.IO.Compression';
        Add-Type -AssemblyName 'System.IO.Compression.FileSystem';
    }
    process {
        try {
            ## Regex for locating the <RepositoryName>-<Branch>\ root directory

            $searchString = '^{0}-{1}\\' -f $Repository, $Branch;
            $replacementString = '{0}\' -f $Repository;
            if ($OverrideRepository) {
                $replacementString = '{0}\' -f $OverrideRepository;
            }
            
            foreach ($zipArchiveEntry in $InputObject) {

                if ($zipArchiveEntry.FullName.Contains('/')) {
                    ## We need to create the directory path as the ExtractToFile extension method won't do this and will throw an exception
                    $pathSplit = $zipArchiveEntry.FullName.Split('/');
                    $relativeDirectoryPath = New-Object System.Text.StringBuilder;

                    ## Generate the relative directory name
                    for ($pathSplitPart = 0; $pathSplitPart -lt ($pathSplit.Count -1); $pathSplitPart++) {
                        [ref] $null = $relativeDirectoryPath.AppendFormat('{0}\', $pathSplit[$pathSplitPart]); 
                    }
                    ## Rename the GitHub \<RepositoryName>-<Branch>\ root directory to \<RepositoryName>\
                    $relativePath = ($relativeDirectoryPath.ToString() -replace $searchString, $replacementString).TrimEnd('\');
         
                    ## Create the destination directory path, joining the relative directory name
                    $directoryPath = Join-Path -Path $DestinationPath -ChildPath $relativePath;
                    [ref] $null = NewDirectory -Path $directoryPath;
                        
                    $fullDestinationFilePath = Join-Path -Path $directoryPath -ChildPath $zipArchiveEntry.Name;
                } # end if
                else {
                    ## Just a file in the root so just use the $DestinationPath
                    $fullDestinationFilePath = Join-Path -Path $DestinationPath -ChildPath $zipArchiveEntry.Name;
                } # end else

                if ([System.String]::IsNullOrEmpty($zipArchiveEntry.Name)) {
                    ## This is a folder and we need to create the directory path as the
                    ## ExtractToFile extension method won't do this and will throw an exception
                    $pathSplit = $zipArchiveEntry.FullName.Split('/');
                    $relativeDirectoryPath = New-Object System.Text.StringBuilder;
                
                    ## Generate the relative directory name
                    for ($pathSplitPart = 0; $pathSplitPart -lt ($pathSplit.Count -1); $pathSplitPart++) {
                        [ref] $null = $relativeDirectoryPath.AppendFormat('{0}\', $pathSplit[$pathSplitPart]); 
                    }
                    
                    ## Rename the GitHub \<RepositoryName>-<Branch>\ root directory to \<RepositoryName>\
                    $relativePath = ($relativeDirectoryPath.ToString() -replace $searchString, $replacementString).TrimEnd('\');
         
                    ## Create the destination directory path, joining the relative directory name
                    $directoryPath = Join-Path -Path $DestinationPath -ChildPath $relativePath;
                    [ref] $null = NewDirectory -Path $directoryPath;
                        
                    $fullDestinationFilePath = Join-Path -Path $directoryPath -ChildPath $zipArchiveEntry.Name;
                }
                elseif (-not $Force -and (Test-Path -Path $fullDestinationFilePath -PathType Leaf)) {
                    ## Are we overwriting existing files (-Force)?
                    Write-Warning ($localized.TargetFileExistsWarning -f $fullDestinationFilePath);
                }
                else {
                    ## Just overwrite any existing file
                    if ($Force -or $PSCmdlet.ShouldProcess($fullDestinationFilePath, 'Expand')) {
                        Write-Debug ($localized.ExtractingZipArchiveEntry -f $fullDestinationFilePath);
                        [System.IO.Compression.ZipFileExtensions]::ExtractToFile($zipArchiveEntry, $fullDestinationFilePath, $true);
                        ## Return a FileInfo object to the pipline
                        Write-Output (Get-Item -Path $fullDestinationFilePath);
                    }
                } # end if
            } # end foreach zipArchiveEntry
        } # end try
        catch {
            Write-Error $_.Exception;
        }
    } # end process
} #end function ExpandZipArchiveItem

function CloseZipArchive {
<#
    .SYNOPSIS
        Tidies up and closes Zip Archive and file handles
#>
    [CmdletBinding()]
    param ()
    process {
        Write-Verbose ($localized.ClosingZipArchive -f $Path);
        if ($null -ne $zipArchive) {
            $zipArchive.Dispose();
        }
        if ($null -ne $fileStream) {
            $fileStream.Close();
        }
    } # end process
} #end function CloseZipArchive

function NewDirectory {
    <#
        .SYNOPSIS
           Creates a file system directory.
        .DESCRIPTION
           The New-Directory cmdlet will create the target directory if it doesn't already
           exist. If the target path already exists, the cmdlet does nothing.
        .INPUTS
           You can pipe multiple strings or multiple System.IO.DirectoryInfo
           objects to this cmdlet.
        .OUTPUTS
           System.IO.DirectoryInfo
        .NOTES
            This is an internal function and should not be called directly.
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByString', SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([System.IO.DirectoryInfo])]
    param (
        # Target filesystem directory to create
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName, Position = 0, ParameterSetName = 'ByDirectoryInfo')]
        [ValidateNotNullOrEmpty()] [System.IO.DirectoryInfo[]] $InputObject,
        
        # Target filesystem directory to create
        [Parameter(Mandatory, ValueFromPipelineByPropertyName, Position = 0, ParameterSetName = 'ByString')]
        [ValidateNotNullOrEmpty()] [Alias('PSPath')] [System.String[]] $Path
    )
    begin {
        Write-Debug ('Using parameter set ''{0}''.' -f $PSCmdlet.ParameterSetName);
    }
    process {
        switch ($PSCmdlet.ParameterSetName) {
            'ByString' {
                foreach ($directoryPath in $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)) {
                    Write-Debug ('Testing target directory ''{0}''.' -f $directoryPath);
                    if (-not (Test-Path -Path $directoryPath -PathType Container)) {
                        if ($PSCmdlet.ShouldProcess($directoryPath, 'Create')) {
                            Write-Verbose ($localized.CreatingDirectory -f $directoryPath);
                            Write-Output (New-Item -Path $directoryPath -ItemType Directory);
                        }
                    }
                    else {
                        Write-Debug ('Target directory ''{0}'' already exists.' -f $Directory);
                        Write-Output (Get-Item -Path $directoryPath);
                    }
                } # end foreach
            } # end ByString

            'ByDirectoryInfo' {
                 foreach ($directoryInfo in $InputObject) {
                    Write-Debug ('Testing target directory ''{0}''.' -f $directoryInfo.FullName);
                    if (-not ($directoryInfo.Exists)) {
                        if ($PSCmdlet.ShouldProcess($directoryInfo.FullName, 'Create')) {
                            Write-Verbose ($localized.CreatingDirectory -f $directoryInfo.FullName);
                            Write-Output (New-Item -Path $directoryInfo.FullName -ItemType Directory);
                        }
                    }
                    else {
                        Write-Debug ('Target directory ''{0}'' already exists.' -f $directoryInfo.FullName);
                        Write-Output $directoryInfo;
                    }
                } # end foreach
            } #end ByDirectoryInfo
        } #end switch
    } # end process
} #end function NewDirectory

function ResolveGitHubUri {
<#
    .SYNOPSIS
        Resolves the correct GitHub URI for the specified Owner, Repository and Branch.
#>
    [CmdletBinding()]
    [OutputType([System.Uri])]
    param (
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [System.String] $Owner,
        
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [System.String] $Repository,
        
        [Parameter(ValueFromPipelineByPropertyName)] [ValidateNotNullOrEmpty()]
        [System.String] $Branch = 'master'
    )
    process {
        $uri = 'https://github.com/{0}/{1}/archive/{2}.zip' -f $Owner, $Repository, $Branch;
        return New-Object -TypeName System.Uri -ArgumentList $uri;
    } #end process
} #end function ResolveGitHubUri

function Install-GitHubRepository {
<#
    .SYNOPSIS
        Downloads, extracts and installs a repository directly from GitHub.
    .DESCRIPTION
        The Install-GitHubRepository cmdlet will download and extract a GitHub repository. This will typically be development PowerShell modules or DSC resources.
        
        Install-GitHubRepository is primary intended to help bootstrap the installation of Powershell modules and DSC resources that have not (yet) been published to the PowerShell Gallery or have been updated on a development branch and are needed for testing purposes.
    .PARAMETER Owner
        Specifies the owner of the GitHub repository from whom to download the module.
    .PARAMETER Repository
        Specifies the GitHub repository name to download.
    .PARAMETER Branch
        Specifies the specific Git repository branch to download. If this is not specified it defaults to the 'master' branch.
    .PARAMETER DestinationPath
        Specifies the path to the folder in which you want the command to save GitHub repository. Enter the path to a folder, but do not specify a file name or file name extension. If this parameter is not specified, it defaults to the '$env:ProgramFiles\WindowsPowershell\Modules' directory.
    .PARAMETER OverrideRepository
        Specifies overriding the repository name when it's expanded to disk. Use this parameter when the extracted Zip file path does not meet your requirements, i.e. when the repository name does not match the Powershell module name.
    .PARAMETER Force
        Forces the extraction of files from an archive file. By default, any files that exist on the local file system are not overwritten.
    .PARAMETER Clean
        Removes the existing repository folder from the local file system before extracting the archive. This ensures that local repository matches the source GitHub repository. Note: this should only be used with PowerShell module/DSC repositories.
#>
    [CmdletBinding(DefaultParameterSetName = 'Clean')]
    [OutputType([System.IO.DirectoryInfo])]
    param (
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [System.String] $Owner,
        
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [System.String] $Repository,
        
        [Parameter(ValueFromPipelineByPropertyName)] [ValidateNotNullOrEmpty()]
        [System.String] $Branch = 'master',
        
        [Parameter(ValueFromPipelineByPropertyName)] [ValidateNotNullOrEmpty()]
        [System.String] $DestinationPath = "$env:ProgramFiles\WindowsPowershell\Modules",
        
        [Parameter(ValueFromPipelineByPropertyName)] [ValidateNotNullOrEmpty()]
        [System.String] $OverrideRepository,
        
        [Parameter(ValueFromPipelineByPropertyName, ParameterSetName = 'Force')]
        [System.Management.Automation.SwitchParameter] $Force,
        
        [Parameter(ValueFromPipelineByPropertyName, ParameterSetName = 'Clean')]
        [System.Management.Automation.SwitchParameter] $Clean
    )
    process {
        $uri = ResolveGitHubUri -Owner $Owner -Repository $Repository -Branch $Branch;
        $tempDestinationFilename = '{0}-{1}.zip' -f $Repository, $Branch;
        $tempDestinationPath = Join-Path -Path $env:TEMP -ChildPath $tempDestinationFilename;
        [ref] $null = Invoke-WebRequest -Uri $uri.AbsoluteUri -OutFile $tempDestinationPath;
        Unblock-File -Path $tempDestinationPath;

        $expandZipArchiveParams = @{
            Path = $tempDestinationPath;
            DestinationPath = $DestinationPath;
            Repository = $Repository;
            Branch = $Branch;
            Force = $Force;
            Clean = $Clean;
        }
        if ($OverrideRepository) {
            $expandZipArchiveParams['OverrideRepository'] = $OverrideRepository;
        }
        [ref] $null = ExpandZipArchive @expandZipArchiveParams;
        
        $modulePath = Join-Path -Path $DestinationPath -ChildPath $Repository;
        if ($OverrideRepository) { $modulePath = Join-Path -Path $DestinationPath -ChildPath $OverrideRepository; }
        
        return (Get-Item -Path $modulePath);
    } #end process
} #end function Install-GitHubRepository
