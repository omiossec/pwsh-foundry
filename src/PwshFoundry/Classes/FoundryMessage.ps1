#Requires -Version 7.0

class FoundryMessage {
    hidden [string] $SystemPrompt
    hidden [string] $UserPrompt

    static [string] $DefaultSystemPrompt = 'You are a helpful assistant'

    FoundryMessage([string]$userPrompt) {
        if ([string]::IsNullOrWhiteSpace($userPrompt)) {
            throw [System.ArgumentException]::new(
                'User prompt cannot be null or empty.',
                'userPrompt'
            )
        }
        $this.UserPrompt   = $userPrompt
        $this.SystemPrompt = [FoundryMessage]::DefaultSystemPrompt
    }

    FoundryMessage([string]$userPrompt, [string]$systemPrompt) {
        if ([string]::IsNullOrWhiteSpace($userPrompt)) {
            throw [System.ArgumentException]::new(
                'User prompt cannot be null or empty.',
                'userPrompt'
            )
        }
        $this.UserPrompt   = $userPrompt
        $this.SystemPrompt = if ([string]::IsNullOrWhiteSpace($systemPrompt)) {
            [FoundryMessage]::DefaultSystemPrompt
        } else {
            $systemPrompt
        }
    }

    [hashtable[]] GetMessages() {
        return @(
            @{ role = 'system'; content = $this.SystemPrompt }
            @{ role = 'user';   content = $this.UserPrompt   }
        )
    }
}
