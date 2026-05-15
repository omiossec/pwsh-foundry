#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0' }

BeforeAll {
    Import-Module "$PSScriptRoot/../src/PwshFoundry/PwshFoundry.psd1" -Force
}

Describe 'Get-FoundryVersion' {
    Context 'When CLI is available' {
        BeforeAll {
            Mock -ModuleName PwshFoundry Invoke-FoundryCli { '0.9.0' }
        }

        It 'returns a version string' {
            $result = Get-FoundryVersion
            $result | Should -Be '0.9.0'
        }
    }

    Context 'When CLI is missing' {
        BeforeAll {
            Mock -ModuleName PwshFoundry Test-FoundryCli {
                throw [System.IO.FileNotFoundException] 'Foundry CLI not found.'
            }
            Mock -ModuleName PwshFoundry Invoke-FoundryCli { Test-FoundryCli }
        }

        It 'throws a terminating error' {
            { Get-FoundryVersion } | Should -Throw
        }
    }
}
