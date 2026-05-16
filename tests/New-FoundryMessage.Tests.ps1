#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0' }

BeforeAll {
    Import-Module "$PSScriptRoot/../src/PwshFoundry/PwshFoundry.psd1" -Force
}

Describe 'New-FoundryMessage' {

    Context 'UserPrompt only (no SystemPrompt supplied)' {
        It 'returns a FoundryMessage instance' {
            $result = New-FoundryMessage -UserPrompt 'Hello'
            $result.GetType().Name | Should -Be 'FoundryMessage'
        }

        It 'stores the user prompt' {
            $messages = (New-FoundryMessage -UserPrompt 'Hello').GetMessages()
            $messages[1].role    | Should -Be 'user'
            $messages[1].content | Should -Be 'Hello'
        }

        It 'uses the default system prompt' {
            InModuleScope PwshFoundry {
                $messages = (New-FoundryMessage -UserPrompt 'Hello').GetMessages()
                $messages[0].role    | Should -Be 'system'
                $messages[0].content | Should -Be ([FoundryMessage]::DefaultSystemPrompt)
            }
        }
    }

    Context 'UserPrompt and SystemPrompt supplied' {
        It 'stores the custom system prompt' {
            $messages = (New-FoundryMessage -UserPrompt 'What is AI?' -SystemPrompt 'You are an expert.').GetMessages()
            $messages[0].role    | Should -Be 'system'
            $messages[0].content | Should -Be 'You are an expert.'
        }

        It 'stores the user prompt' {
            $messages = (New-FoundryMessage -UserPrompt 'What is AI?' -SystemPrompt 'You are an expert.').GetMessages()
            $messages[1].role    | Should -Be 'user'
            $messages[1].content | Should -Be 'What is AI?'
        }

        It 'falls back to the default system prompt when SystemPrompt is empty' {
            InModuleScope PwshFoundry {
                $messages = (New-FoundryMessage -UserPrompt 'Hello' -SystemPrompt '').GetMessages()
                $messages[0].content | Should -Be ([FoundryMessage]::DefaultSystemPrompt)
            }
        }

        It 'falls back to the default system prompt when SystemPrompt is whitespace' {
            InModuleScope PwshFoundry {
                $messages = (New-FoundryMessage -UserPrompt 'Hello' -SystemPrompt '   ').GetMessages()
                $messages[0].content | Should -Be ([FoundryMessage]::DefaultSystemPrompt)
            }
        }
    }

    Context 'Invalid UserPrompt' {
        It 'throws when UserPrompt is empty' {
            { New-FoundryMessage -UserPrompt '' } | Should -Throw
        }

        It 'throws when UserPrompt is whitespace' {
            { New-FoundryMessage -UserPrompt '   ' } | Should -Throw
        }

        It 'throws when UserPrompt is not provided' {
            { New-FoundryMessage } | Should -Throw
        }
    }

    Context 'GetMessages return structure' {
        It 'returns exactly two entries' {
            $messages = (New-FoundryMessage -UserPrompt 'Hello').GetMessages()
            $messages.Count | Should -Be 2
        }

        It 'returns system message first, user message second' {
            $messages = (New-FoundryMessage -UserPrompt 'Hello').GetMessages()
            $messages[0].role | Should -Be 'system'
            $messages[1].role | Should -Be 'user'
        }

        It 'each entry has role and content keys' {
            $messages = (New-FoundryMessage -UserPrompt 'Hello').GetMessages()
            foreach ($msg in $messages) {
                $msg.ContainsKey('role')    | Should -BeTrue
                $msg.ContainsKey('content') | Should -BeTrue
            }
        }
    }
}
