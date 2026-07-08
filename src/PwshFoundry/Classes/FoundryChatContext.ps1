#Requires -Version 7.0

class FoundryChatContext {
    hidden [string] $SystemPrompt
    hidden [System.Collections.Generic.List[hashtable]] $Messages

    static [string] $DefaultSystemPrompt = 'You are a helpful assistant'

    FoundryChatContext([string]$userPrompt) {
        if ([string]::IsNullOrWhiteSpace($userPrompt)) {
            throw [System.ArgumentException]::new(
                'User prompt cannot be null or empty.',
                'userPrompt'
            )
        }

        $this.SystemPrompt = [FoundryChatContext]::DefaultSystemPrompt

        $this.Messages = [System.Collections.Generic.List[hashtable]]::new()
        $this.Messages.Add(@{ role = 'system'; content = $this.SystemPrompt })
        $this.Messages.Add(@{ role = 'user';   content = $userPrompt })
    }

    FoundryChatContext([string]$userPrompt, [string]$systemPrompt) {
        if ([string]::IsNullOrWhiteSpace($userPrompt)) {
            throw [System.ArgumentException]::new(
                'User prompt cannot be null or empty.',
                'userPrompt'
            )
        }

        $this.SystemPrompt = if ([string]::IsNullOrWhiteSpace($systemPrompt)) {
            [FoundryChatContext]::DefaultSystemPrompt
        } else {
            $systemPrompt
        }

        $this.Messages = [System.Collections.Generic.List[hashtable]]::new()
        $this.Messages.Add(@{ role = 'system'; content = $this.SystemPrompt })
        $this.Messages.Add(@{ role = 'user';   content = $userPrompt })
    }

    [void] AddUserPrompt([string]$userPrompt) {
        if ([string]::IsNullOrWhiteSpace($userPrompt)) {
            throw [System.ArgumentException]::new(
                'User prompt cannot be null or empty.',
                'userPrompt'
            )
        }

        $this.Messages.Add(@{ role = 'user'; content = $userPrompt })
    }

    [void] AddAssistantResponse([string]$assistantResponse) {
        if ([string]::IsNullOrWhiteSpace($assistantResponse)) {
            throw [System.ArgumentException]::new(
                'Assistant response cannot be null or empty.',
                'assistantResponse'
            )
        }

        $this.Messages.Add(@{ role = 'assistant'; content = $assistantResponse })
    }

    [hashtable[]] GetMessages() {
        return $this.Messages.ToArray()
    }
}
