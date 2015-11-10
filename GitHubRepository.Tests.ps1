#requires -RunAsAdministrator
#requires -Version 4

$moduleName = 'GitHubRepository';
if (!$PSScriptRoot) { # $PSScriptRoot is not defined in 2.0
    $PSScriptRoot = [System.IO.Path]::GetDirectoryName($MyInvocation.MyCommand.Path)
}
$repoRoot = (Resolve-Path $PSScriptRoot).Path;

Import-Module (Join-Path -Path $RepoRoot -ChildPath "$moduleName.psm1") -Force;

Describe $moduleName {
    
    InModuleScope $moduleName {

        Context 'Validates "NewDirectory" method' {

            ## Need to resolve actual filesystem path for System.IO.DirectoryInfo calls
            $testDirectoryPath = "$((Get-PSdrive -Name TestDrive).Root)\NewDirectory";

            BeforeEach {
                Remove-Item -Path 'TestDrive:\NewDirectory' -Force -ErrorAction SilentlyContinue;
            }
        
	        It 'Returns a "System.IO.DirectoryInfo" object if target "Path" already exists' {
                $testDirectoryPath = "$env:SystemRoot";
                Test-Path -Path $testDirectoryPath | Should Be $true;
		        
                (NewDirectory -Path $testDirectoryPath) -is [System.IO.DirectoryInfo] | Should Be $true;
	        }

            It 'Returns a "System.IO.DirectoryInfo" object if target "Path" does not exist' {
                (NewDirectory -Path $testDirectoryPath) -is [System.IO.DirectoryInfo] | Should Be $true;
            }

            It 'Creates target "Path" if it does not exist' {
                Test-Path -Path $testDirectoryPath | Should Be $false;
                NewDirectory -Path $testDirectoryPath;
                
                Test-Path -Path $testDirectoryPath | Should Be $true;
            }

            It 'Returns a "System.IO.DirectoryInfo" object if target "DirectoryInfo" already exists' {
                $testDirectoryPath = "$env:SystemRoot";
                Test-Path -Path $testDirectoryPath | Should Be $true;
                $directoryInfo = New-Object -TypeName System.IO.DirectoryInfo -ArgumentList $testDirectoryPath;
		        
                ($directoryInfo | NewDirectory ) -is [System.IO.DirectoryInfo] | Should Be $true;
	        }

            It 'Returns a "System.IO.DirectoryInfo" object if target "DirectoryInfo" does not exist' {
                Test-Path -Path $testDirectoryPath | Should Be $false;
                NewDirectory -Path $testDirectoryPath;
                Test-Path -Path $testDirectoryPath | Should Be $true;
                
                (NewDirectory -Path $testDirectoryPath) -is [System.IO.DirectoryInfo] | Should Be $true;
            }

            It 'Creates target "DirectoryInfo" if it does not exist' {
                Test-Path -Path $testDirectoryPath | Should Be $false;
                $directoryInfo = New-Object -TypeName System.IO.DirectoryInfo -ArgumentList $testDirectoryPath;
                
                $directoryInfo | NewDirectory;
                
                Test-Path -Path $testDirectoryPath | Should Be $true;
            }

        } #end context Validates "NewDirectory" method

        Context 'Validates "ResolveGitHubUri" method' {

            It 'Returns a "System.Uri" object type' {
                $testOwner = 'TestOwner';
                $testRepository = 'TestRepository';
                
                $uri = ResolveGitHubUri -Owner $testOwner -Repository $testRepository;
                
                $uri -is [System.Uri] | Should Be $true;
	        }

            It 'Defaults to "master" branch' {
                $testOwner = 'TestOwner';
                $testRepository = 'TestRepository';
                
                $uri = ResolveGitHubUri -Owner $testOwner -Repository $testRepository;

                $uri -match "/$testOwner/$testRepository/archive/master.zip" | Should Be $true;
            }

        } #end context Validates "ResolveGitHubUri" method

        Context 'Validates "Install-GitHubRepository" method' {

            It 'Returns a "System.IO.DirectoryInfo" object type' {
                $testOwner = 'TestOwner';
                $testRepository = 'TestRepository';
                $testDestinationPath = 'TestDrive:\';
                Mock Invoke-WebRequest -MockWith { New-Item -Path $OutFile -ItemType File -Force -ErrorAction SilentlyContinue; }
                Mock ExpandZipArchive -MockWith { New-Item -Path "$DestinationPath\$Repository" -ItemType Directory -Force -ErrorAction SilentlyContinue; }

                $directoryInfo = Install-GitHubRepository -Owner $testOwner -Repository $testRepository -DestinationPath $testDestinationPath;

                $directoryInfo -is [System.IO.DirectoryInfo] | Should Be $true;
            }

            It 'Calls "ExpandZipArchive" with "OverrideRepository" when specified' {
                $testOwner = 'TestOwner';
                $testRepository = 'TestRepository';
                $testOverrideRepository = 'MyRepository';
                $testDestinationPath = 'TestDrive:\';
                Mock Invoke-WebRequest -MockWith { New-Item -Path $OutFile -ItemType File -Force -ErrorAction SilentlyContinue; }
                Mock ExpandZipArchive -ParameterFilter { -not [String]::IsNullOrEmpty($OverrideRepository) } -MockWith { New-Item -Path "$DestinationPath\$OverrideRepository" -ItemType Directory -Force -ErrorAction SilentlyContinue; }
                
                Install-GitHubRepository -Owner $testOwner -Repository $testRepository -DestinationPath $testDestinationPath -OverrideRepository $testOverrideRepository;

                Assert-MockCalled ExpandZipArchive -ParameterFilter { -not [String]::IsNullOrEmpty($OverrideRepository) } -Scope It;
            }

            It 'Calls "Invoke-WebRequest" with "/archive/master.zip" by default' {
                $testOwner = 'TestOwner';
                $testRepository = 'TestRepository';
                $testDestinationPath = 'TestDrive:\';
                Mock Invoke-WebRequest -ParameterFilter { $Uri -match '/archive/master.zip' } -MockWith { New-Item -Path $OutFile -ItemType File -Force -ErrorAction SilentlyContinue; }
                Mock ExpandZipArchive { New-Item -Path "$DestinationPath\$Repository" -ItemType Directory -Force -ErrorAction SilentlyContinue; }
                
                Install-GitHubRepository -Owner $testOwner -Repository $testRepository -DestinationPath $testDestinationPath;

                Assert-MockCalled Invoke-WebRequest -ParameterFilter { $Uri -match '/archive/master.zip' } -Scope It;
            }

            It 'Calls "Invoke-WebRequest" with "/archive/dev.zip" when "Branch" is specified' {
                $testOwner = 'TestOwner';
                $testRepository = 'TestRepository';
                $testDestinationPath = 'TestDrive:\';
                $testBranch = 'dev';
                Mock Invoke-WebRequest -ParameterFilter { $Uri -match "/archive/$testBranch.zip$" } -MockWith { New-Item -Path $OutFile -ItemType File -Force -ErrorAction SilentlyContinue; }
                Mock ExpandZipArchive { New-Item -Path "$DestinationPath\$Repository" -ItemType Directory -Force -ErrorAction SilentlyContinue; }
                
                Install-GitHubRepository -Owner $testOwner -Repository $testRepository -DestinationPath $testDestinationPath -Branch $testBranch;

                Assert-MockCalled Invoke-WebRequest -ParameterFilter { $Uri -match "/archive/$testBranch.zip$" } -Scope It;
            }

        } #end context Validates "Install-GitHubRepository" method

    } #end InModuleScope

} #end describe
