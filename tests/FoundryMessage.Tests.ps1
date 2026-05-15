#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0' }

BeforeAll {
    Import-Module "$PSScriptRoot/../src/PwshFoundry/PwshFoundry.psd1" -Force
}

Describe 'FoundryMessage' {

    Context 'Single-argument constructor (user prompt only)' {
        It 'creates an instance without throwing' {
            { InModuleScope PwshFoundry { [FoundryMessage]::new('Hello') } } | Should -Not -Throw
        }

        It 'uses the default system prompt' {
            $messages = InModuleScope PwshFoundry {
                [FoundryMessage]::new('Hello').GetMessages()
            }
            $messages[0].role    | Should -Be 'system'
            $messages[0].content | Should -Be ([FoundryMessage]::DefaultSystemPrompt)
        }

        It 'stores the user prompt' {
            $messages = InModuleScope PwshFoundry {
                [FoundryMessage]::new('Hello').GetMessages()
            }
            $messages[1].role    | Should -Be 'user'
            $messages[1].content | Should -Be 'Hello'
        }

        It 'throws when user prompt is empty' {
            { InModuleScope PwshFoundry { [FoundryMessage]::new('') } } | Should -Throw
        }

        It 'throws when user prompt is whitespace' {
            { InModuleScope PwshFoundry { [FoundryMessage]::new('   ') } } | Should -Throw
        }

        It 'throws when user prompt is null' {
            { InModuleScope PwshFoundry { [FoundryMessage]::new($null) } } | Should -Throw
        }
    }

    Context 'Two-argument constructor (user prompt + system prompt)' {
        It 'stores both prompts' {
            $messages = InModuleScope PwshFoundry {
                [FoundryMessage]::new('What is AI?', 'You are an expert.').GetMessages()
            }
            $messages[0].role    | Should -Be 'system'
            $messages[0].content | Should -Be 'You are an expert.'
            $messages[1].role    | Should -Be 'user'
            $messages[1].content | Should -Be 'What is AI?'
        }

        It 'falls back to the default system prompt when system prompt is empty' {
            $messages = InModuleScope PwshFoundry {
                [FoundryMessage]::new('Hello', '').GetMessages()
            }
            $messages[0].content | Should -Be ([FoundryMessage]::DefaultSystemPrompt)
        }

        It 'falls back to the default system prompt when system prompt is whitespace' {
            $messages = InModuleScope PwshFoundry {
                [FoundryMessage]::new('Hello', '   ').GetMessages()
            }
            $messages[0].content | Should -Be ([FoundryMessage]::DefaultSystemPrompt)
        }

        It 'throws when user prompt is empty' {
            { InModuleScope PwshFoundry { [FoundryMessage]::new('', 'You are an expert.') } } | Should -Throw
        }

        It 'throws when user prompt is null' {
            { InModuleScope PwshFoundry { [FoundryMessage]::new($null, 'You are an expert.') } } | Should -Throw
        }
    }

    Context 'GetMessages return structure' {
        It 'returns exactly two entries' {
            $messages = InModuleScope PwshFoundry {
                [FoundryMessage]::new('Hello').GetMessages()
            }
            $messages.Count | Should -Be 2
        }

        It 'returns system message first, user message second' {
            $messages = InModuleScope PwshFoundry {
                [FoundryMessage]::new('Hello').GetMessages()
            }
            $messages[0].role | Should -Be 'system'
            $messages[1].role | Should -Be 'user'
        }

        It 'each entry has a role and a content key' {
            $messages = InModuleScope PwshFoundry {
                [FoundryMessage]::new('Hello').GetMessages()
            }
            foreach ($msg in $messages) {
                $msg.ContainsKey('role')    | Should -BeTrue
                $msg.ContainsKey('content') | Should -BeTrue
            }
        }
    }
}
